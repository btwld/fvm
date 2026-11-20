import 'dart:io';
import 'dart:math' as math;

import 'package:dart_mappable/dart_mappable.dart';
import 'package:date_format/date_format.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import '../models/cache_flutter_version_model.dart';
import '../services/logger_service.dart';
import 'constants.dart';
import 'extensions.dart';
import 'git_utils.dart';

/// Checks if [name] is a valid Flutter release channel.
bool isFlutterChannel(String name) {
  return kFlutterChannels.contains(name);
}

/// Converts Flutter versions and channels to comparable semver strings.
/// Assigns weights: git commits (500.0.0), main/master (400.0.0),
/// stable (300.0.0), beta (200.0.0), dev (100.0.0), invalid (0.0.0).
String assignVersionWeight(String version) {
  /// Assign version number to continue to work with semver
  if (isPossibleGitCommit(version)) {
    version = '500.0.0';
  } else {
    switch (version) {
      case 'main':
      case 'master':
        version = '400.0.0';
        break;
      case 'stable':
        version = '300.0.0';
        break;
      case 'beta':
        version = '200.0.0';
        break;
      case 'dev':
        version = '100.0.0';
        break;
      default:
    }
  }

  if (version.contains('v')) {
    version = version.replaceFirst('v', '');
  }

  bool isCustom = version.contains('custom_');

  if (isCustom) {
    version = version.replaceFirst('custom_', '');
  }

  try {
    // Validate version format - throws if invalid
    final _ = Version.parse(version);
  } on Exception {
    if (isCustom) {
      return '400.0.0';
    }

    return '0.0.0';
  }

  return version;
}

/// Formats a DateTime as "Month Day, Year" (e.g., "Jan 15, 2024").
String friendlyDate(DateTime dateTime) {
  return formatDate(dateTime, [M, ' ', d, ', ', yyyy]);
}

/// Returns true if running inside Visual Studio Code.
bool isVsCode() => Platform.environment['TERM_PROGRAM'] == 'vscode';

/// Parsed Flutter version information from `flutter --version` output.
class FlutterVersionOutput {
  /// The Flutter SDK version (e.g., "3.15.0").
  final String? flutterVersion;

  /// The Flutter release channel (e.g., "stable", "beta", "dev").
  final String? channel;

  /// The Dart SDK version (e.g., "3.2.0").
  final String? dartVersion;

  /// The Dart build version including build metadata (e.g., "3.2.0-134.1.beta").
  final String? dartBuildVersion;

  /// The Flutter framework Git revision hash.
  final String? frameworkRevision;

  /// The Flutter engine Git revision hash.
  final String? engineRevision;

  const FlutterVersionOutput({
    this.flutterVersion,
    this.channel,
    this.dartVersion,
    this.dartBuildVersion,
    this.frameworkRevision,
    this.engineRevision,
  });

  @override
  String toString() {
    return 'FlutterVersionOutput(flutterVersion: $flutterVersion, channel: $channel, dartVersion: $dartVersion, dartBuildVersion: $dartBuildVersion, frameworkRevision: $frameworkRevision, engineRevision: $engineRevision)';
  }
}

/// Parses Flutter version output from `flutter --version` command.
///
/// Example input formats:
/// ```
/// Flutter 3.15.0-15.1.pre • channel beta • https://github.com/flutter/flutter.git
/// Framework • revision b2ec15bfa3 (5 days ago) • 2023-09-14 15:31:44 -0500
/// Engine • revision 5c86194494
/// Tools • Dart 3.2.0 (build 3.2.0-134.1.beta) • DevTools 2.27.0
/// ```
///
/// ```
/// Flutter 3.10.5 • channel stable • https://github.com/flutter/flutter.git
/// Framework • revision 796c8ef792 (3 months ago) • 2023-06-13 15:51:02 -0700
/// Engine • revision 45f6e00911
/// Tools • Dart 3.0.5 • DevTools 2.23.1
/// ```
///
/// Returns a [FlutterVersionOutput] object with parsed version information.
/// Throws [FormatException] if the content cannot be parsed.
FlutterVersionOutput extractFlutterVersionOutput(String content) {
  final filteredContent = _extractFlutterInfoBlock(content);

  final flutterRegex = RegExp(r'Flutter (\S+)');
  final channelRegex = RegExp(r' channel ([^\s•]+)');
  final dartRegex = RegExp(r'Dart (\S+)(?: \(build (\S+)\))?');
  final frameworkRegex = RegExp(r'Framework • revision (\w+)');
  final engineRegex = RegExp(r'Engine • revision (\w+)');

  final flutterMatch = flutterRegex.firstMatch(filteredContent);
  final channelMatch = channelRegex.firstMatch(filteredContent);
  final dartMatch = dartRegex.firstMatch(filteredContent);
  final frameworkMatch = frameworkRegex.firstMatch(filteredContent);
  final engineMatch = engineRegex.firstMatch(filteredContent);

  if (flutterMatch == null) {
    throw FormatException('Unable to parse Flutter version.');
  }

  if (dartMatch == null) {
    throw FormatException('Unable to parse Dart version.');
  }

  final channel = channelMatch?.group(1)?.trim().toLowerCase();
  if (channel == null || !isFlutterChannel(channel)) {
    throw FormatException('Unable to parse Flutter channel.');
  }

  return FlutterVersionOutput(
    flutterVersion: flutterMatch.group(1)!,
    channel: channel,
    dartVersion: dartMatch.group(1)!,
    dartBuildVersion: dartMatch.group(2) ?? dartMatch.group(1)!,
    frameworkRevision: frameworkMatch?.group(1),
    engineRevision: engineMatch?.group(1),
  );
}

String _extractFlutterInfoBlock(String content) {
  // Ignore anything before "Flutter
  final flutterInfoBlock = content.indexOf('Flutter');
  if (flutterInfoBlock == -1) {
    throw FormatException(
      'Unable to parse Flutter version from the provided content.',
    );
  }

  return content.substring(flutterInfoBlock);
}

/// Extracts Dart version from `dart --version` output.
String extractDartVersionOutput(String input) {
  final RegExp regExp = RegExp(r'Dart SDK version: (\S+)');
  final match = regExp.firstMatch(input);
  if (match != null) {
    return match.group(1)!.trim();
  }
  throw FormatException(
    'No Dart version found in the input string. \n\n $input',
  );
}

/// Validates if a URL is a valid Git repository URL.
///
/// Accepts URLs with or without `.git` suffix, but requires structural
/// validity: allowed scheme, non-empty host (for network URLs), and at
/// least one meaningful path segment.
bool isValidGitUrl(String url) {
  final trimmed = url.trim();

  if (trimmed.isEmpty) {
    return false;
  }

  // Accept scp-like syntax such as git@host:group/repo.git.
  // Skip URLs with :// which are scheme-based, not scp-like.
  if (!trimmed.contains('://') && _isScpLikeGitUrl(trimmed)) {
    return _hasValidRepoPath(_extractScpPath(trimmed));
  }

  // Accept ssh:// urls that use scp shorthand after the scheme.
  const sshScheme = 'ssh://';
  if (trimmed.startsWith(sshScheme)) {
    final remainder = trimmed.substring(sshScheme.length);
    if (_isScpLikeGitUrl(remainder)) {
      return _hasValidRepoPath(_extractScpPath(remainder));
    }
  }

  try {
    final uri = Uri.parse(trimmed);

    if (!uri.hasScheme) {
      return false;
    }

    // Query/fragment suffixes are not valid git remotes.
    if (uri.hasQuery || uri.hasFragment) {
      return false;
    }

    final scheme = uri.scheme.toLowerCase();
    const allowedSchemes = {'https', 'http', 'git', 'ssh', 'file'};
    if (!allowedSchemes.contains(scheme)) {
      return false;
    }

    if (scheme == 'file') {
      return _hasValidRepoPath(uri.path);
    }

    if (uri.host.isEmpty && uri.authority.isEmpty) {
      return false;
    }

    return _hasValidRepoPath(uri.path);
  } on FormatException {
    return false;
  }
}

/// Checks that a path has at least one meaningful segment (e.g., /owner/repo
/// or just repo.git). Accepts paths with or without `.git` suffix.
bool _hasValidRepoPath(String? path) {
  if (path == null || path.isEmpty) return false;

  // scp-like paths may contain query/fragment text; reject those.
  if (path.contains('?') || path.contains('#')) return false;

  // Strip .git suffix for segment analysis
  final cleanPath =
      path.endsWith('.git') ? path.substring(0, path.length - 4) : path;

  final segments = cleanPath.split('/').where((s) => s.isNotEmpty).toList();

  return segments.isNotEmpty;
}

bool _isScpLikeGitUrl(String url) {
  // Matches scp-like syntax: [user@]host:path
  // - user@: optional username with @ separator
  // - host: hostname or IPv6 literal in brackets [::1]
  // - : required colon separator (distinguishes from file paths)
  // - path: required path component
  // Examples: git@github.com:user/repo.git, [::1]:path/to/repo.git
  final scpPattern = RegExp(r'^(?:[^@:/\s]+@)?(?:\[[^\]]+\]|[^:\s]+):[^\s]+$');

  return scpPattern.hasMatch(url);
}

/// Extracts the path portion from an scp-like Git URL.
///
/// Handles two formats:
/// 1. IPv6 host in brackets: [2001:db8::1]:path/to/repo -> path/to/repo
/// 2. Regular host: user@host.com:path/to/repo -> path/to/repo
///
/// Returns null if the URL format is invalid (missing colon separator).
String? _extractScpPath(String url) {
  if (url.startsWith('[')) {
    final closeBracket = url.indexOf(']');
    if (closeBracket == -1) {
      return null;
    }

    final ipv6Separator = url.indexOf(':', closeBracket);

    return ipv6Separator == -1 ? null : url.substring(ipv6Separator + 1);
  }

  final separator = url.indexOf(':');

  return separator == -1 ? null : url.substring(separator + 1);
}

/// Converts string to boolean. Returns null for invalid values.
bool? stringToBool(String value) {
  final lowerCase = value.toLowerCase();
  if (lowerCase == 'true') {
    return true;
  }

  if (lowerCase == 'false') {
    return false;
  }

  return null;
}

/// Formats bytes into human-readable format (e.g., "1.5 GB").
String formatFriendlyBytes(int bytes, [int decimals = 2]) {
  if (bytes <= 0) return '0 B';

  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB'];
  final int suffixIndex = math.min(
    (math.log(bytes) / math.log(1024)).floor(),
    suffixes.length - 1,
  );

  final num scaledValue = bytes / math.pow(1024, suffixIndex);

  return '${scaledValue.toStringAsFixed(decimals)} ${suffixes[suffixIndex]}';
}

/// Calculates total size of a directory recursively.
Future<int> getDirectorySize(Directory dir) async {
  int total = 0;

  await for (FileSystemEntity entity in dir.list(recursive: true)) {
    if (entity is File) {
      total += await entity.length();
    }
  }

  return total;
}

Future<int> _getVersionDirectorySize(
  CacheFlutterVersion version,
  Logger logger,
) async {
  try {
    return await getDirectorySize(version.directory.dir);
  } on FileSystemException catch (e) {
    logger.debug('Cannot access ${version.name} for size calculation: $e');

    return 0;
  } catch (e) {
    // Log error but continue with zero for this directory
    logger.warn('Error calculating size for ${version.name}: $e');

    return 0;
  }
}

/// Calculates total size of all cached Flutter versions in parallel.
Future<int> getFullDirectorySize(
  List<CacheFlutterVersion> versions,
  Logger logger,
) async {
  if (versions.isEmpty) return 0;

  try {
    // Process all directories in parallel with error handling for each
    final sizes = await Future.wait(
      versions.map((version) => _getVersionDirectorySize(version, logger)),
    );

    // Sum all sizes in one operation
    var total = 0;
    for (final size in sizes) {
      total += size;
    }

    return total;
  } catch (e) {
    // Fallback if parallel execution fails
    logger.err(
      'Failed to calculate total directory size due to internal error: $e',
    );

    return 0;
  }
}

/// Updates environment variables by prepending paths to PATH.
Map<String, String> updateEnvironmentVariables(
  List<String> paths,
  Map<String, String> env,
) {
  // Remove duplicates
  paths = paths.toSet().toList();

  final updatedEnvironment = Map.of(env);
  final envPath = env['PATH'] ?? '';
  final separator = Platform.isWindows ? ';' : ':';

  updatedEnvironment['PATH'] = paths.join(separator) + separator + envPath;

  return updatedEnvironment;
}

const skipCopyWith = GenerateMethods.decode |
    GenerateMethods.encode |
    GenerateMethods.stringify |
    GenerateMethods.equals;

/// Recursively searches for a directory and returns the first valid candidate.
///
/// This function traverses up the directory hierarchy until it finds a
/// directory accepted by the [validate] callback, or reaches the root. The
/// optional [debugPrinter] is invoked with debug messages at each step, and
/// defaults to a no-op if not provided.
///
/// If no valid candidate is found, `null` is returned.
T? lookUpDirectoryAncestor<T>({
  required Directory directory,
  required T? Function(Directory) validate,
  void Function(String)? debugPrinter,
}) {
  // ignore: no-empty-block
  debugPrinter ??= (String message) {};
  debugPrinter('Looking up directory: ${directory.path}');
  // Check if the current directory is the root
  final isRootDir = p.rootPrefix(directory.path) == directory.path;

  final result = validate(directory);

  if (result != null) {
    debugPrinter('Found valid candidate: ${directory.path}');

    return result;
  }

  // If we reached the root directory, return the fallback
  if (isRootDir) {
    debugPrinter('No valid directory found');

    return null;
  }

  // Otherwise, recursively search the parent directory
  return lookUpDirectoryAncestor(
    directory: directory.parent,
    validate: validate,
    debugPrinter: debugPrinter,
  );
}
