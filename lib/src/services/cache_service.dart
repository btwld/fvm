import 'dart:io';

import 'package:io/io.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';

import '../models/cache_flutter_version_model.dart';
import '../models/flutter_version_model.dart';
import '../utils/exceptions.dart';
import '../utils/extensions.dart';
import '../utils/file_utils.dart';
import 'base_service.dart';

enum CacheIntegrity {
  valid,
  invalid,
  versionMismatch;

  bool get notValid => !isValid;

  bool get isValid => this == valid;
}

class CacheService extends ContextualService {
  const CacheService(super.context);

  static String _normalizeVersion(String value) {
    if (value.startsWith('v') || value.startsWith('V')) {
      return value.substring(1);
    }

    return value;
  }

  String? _relativeVersionNameFromCachePath(String targetPath) {
    final cacheRoot = path.normalize(context.versionsCachePath);
    final normalizedTarget = path.normalize(targetPath);
    if (!path.isWithin(cacheRoot, normalizedTarget)) {
      return null;
    }

    final relative = path.relative(normalizedTarget, from: cacheRoot);
    if (relative.isEmpty || relative == '.') {
      return null;
    }

    // Convert to POSIX-style path for consistent fork/version parsing
    return path.posix.joinAll(path.split(relative));
  }

  Directory _safeCacheDirectory(List<String> segments) {
    final cacheRoot = path.normalize(context.versionsCachePath);
    final targetPath = path.normalize(path.joinAll([cacheRoot, ...segments]));

    if (!path.isWithin(cacheRoot, targetPath) && targetPath != cacheRoot) {
      throw AppException(
        'Invalid cache path computed outside of the cache directory.',
      );
    }

    return Directory(targetPath);
  }

  Future<bool> _verifyIsExecutable(CacheFlutterVersion version) async {
    final binExists = File(version.flutterExec).existsSync();

    return binExists && await isExecutable(version.flutterExec);
  }

  /// Returns true when the cached version can be treated as a match.
  /// Channels, git refs, custom local SDKs, and missing SDK metadata don't
  /// provide a reliable semantic version to compare, so they are treated as
  /// matching. A custom SDK directory name is a label, not the Flutter
  /// version reported by the SDK.
  bool _verifyVersionMatch(CacheFlutterVersion version) {
    if (version.isChannel) return true;
    if (version.isUnknownRef) return true;
    if (version.isCustom) return true;
    final cached = version.flutterSdkVersion;
    if (cached == null) return true;

    return versionsMatch(version.version, cached);
  }

  /// Heuristic check for a Flutter SDK directory.
  ///
  /// A `version` file or the combination of `.git` + `bin/flutter` indicates
  /// this is a cloned Flutter SDK rather than a fork parent directory.
  bool _looksLikeFlutterSdk(Directory dir) {
    final hasVersionFile = File(path.join(dir.path, 'version')).existsSync();
    if (hasVersionFile) return true;

    final hasGitDir = Directory(path.join(dir.path, '.git')).existsSync();
    final binName = Platform.isWindows ? 'flutter.bat' : 'flutter';
    final hasBin = File(path.join(dir.path, 'bin', binName)).existsSync();

    return hasGitDir && hasBin;
  }

  Link get _globalCacheLink => Link(context.globalCacheLink);

  CacheFlutterVersion? getVersion(FlutterVersion version) {
    final versionDir = getVersionCacheDir(version);
    if (!versionDir.existsSync()) return null;

    return CacheFlutterVersion.fromVersion(version, directory: versionDir.path);
  }

  /// Lists all installed Flutter SDK versions, sorted newest first.
  Future<List<CacheFlutterVersion>> getAllVersions() async {
    final versionsDir = Directory(context.versionsCachePath);
    if (!await versionsDir.exists()) return [];

    final cacheVersions = <CacheFlutterVersion>[];

    Future<void> processDirectory(Directory dir, {String? forkName}) async {
      if (_looksLikeFlutterSdk(dir)) {
        try {
          final name = _relativeVersionNameFromCachePath(dir.path);
          if (name == null) return;
          final version = FlutterVersion.parse(name);

          final cacheVersion = getVersion(version);
          if (cacheVersion != null) {
            cacheVersions.add(cacheVersion);
          }
        } on FormatException catch (e) {
          logger.debug('Skipping invalid version directory ${dir.path}: $e');
        } catch (e) {
          logger.warn('Error processing ${dir.path}: $e');
        }

        return;
      }

      // Non-SDK top-level directories may be fork directories
      if (forkName != null) return;

      final entries = await dir.list().toList();
      for (var entry in entries) {
        if (entry.path.isDir()) {
          final subDirName = path.basename(entry.path);
          if (subDirName.startsWith('.')) continue;
          await processDirectory(
            Directory(entry.path),
            forkName: path.basename(dir.path),
          );
        }
      }
    }

    final topLevelEntries = await versionsDir.list().toList();
    for (var entry in topLevelEntries) {
      if (entry.path.isDir()) {
        final dirName = path.basename(entry.path);
        if (dirName.startsWith('.')) continue;
        await processDirectory(Directory(entry.path));
      }
    }

    cacheVersions.sort((a, b) => b.compareTo(a));

    return cacheVersions;
  }

  /// Removes a cached Flutter SDK version and cleans up empty fork directories.
  Future<void> remove(FlutterVersion version) async {
    final versionDir = getVersionCacheDir(version);
    if (versionDir.existsSync()) {
      await deleteDirectoryWithRetry(versionDir);
    }

    // If this is a fork version and the fork directory is now empty, clean it up
    if (version.fromFork) {
      final forkDir = Directory(
        path.join(context.versionsCachePath, version.fork!),
      );
      if (forkDir.existsSync()) {
        final entries = forkDir.listSync();
        if (entries.isEmpty) {
          await deleteDirectoryWithRetry(forkDir);
        }
      }
    }
  }

  /// Returns the cache directory for [version].
  ///
  /// Fork versions resolve to `versionsCachePath/fork/version`,
  /// standard versions to `versionsCachePath/version`.
  Directory getVersionCacheDir(FlutterVersion version) {
    if (version.fromFork) {
      return _safeCacheDirectory([version.fork!, version.version]);
    }

    return _safeCacheDirectory([version.name]);
  }

  /// The name [getAllVersions] reports for [version] once it is installed.
  ///
  /// Derived from the cache directory rather than from [version] directly, so
  /// it stays correct where the directory drops part of the requested version:
  /// a forked `x@channel` pin installs to `<fork>/x`, so the cache only ever
  /// knows it as `<fork>/x`. Callers matching a project's pin against installed
  /// SDKs must compare this, not [FlutterVersion.nameWithAlias].
  ///
  /// This is a path derivation, not an existence check. It returns null only
  /// when the computed directory is not inside the versions cache.
  String? installedNameOf(FlutterVersion version) {
    try {
      return _relativeVersionNameFromCachePath(
        getVersionCacheDir(version).path,
      );
    } on AppException {
      return null;
    }
  }

  // For backward compatibility - used by existing string-based calls
  @Deprecated('Use getVersionCacheDir(FlutterVersion) instead')
  Directory getVersionCacheDirByName(String version) {
    return _safeCacheDirectory([version]);
  }

  // Verifies that cache can be executed and matches version
  Future<CacheIntegrity> verifyCacheIntegrity(
    CacheFlutterVersion version,
  ) async {
    final isExecutable = await _verifyIsExecutable(version);
    final versionsMatch = _verifyVersionMatch(version);

    if (!isExecutable) return CacheIntegrity.invalid;
    if (!versionsMatch) return CacheIntegrity.versionMismatch;

    return CacheIntegrity.valid;
  }

  void setGlobal(CacheFlutterVersion version) {
    _globalCacheLink.createLink(version.directory);
  }

  void unlinkGlobal() {
    if (_globalCacheLink.existsSync()) {
      _globalCacheLink.deleteSync();
    }
  }

  /// Returns the global [CacheFlutterVersion], or null if none is set.
  CacheFlutterVersion? getGlobal() {
    final version = getGlobalVersion();
    if (version == null) return null;

    try {
      final validVersion = FlutterVersion.parse(version);

      return getVersion(validVersion);
    } on FormatException catch (e) {
      logger.warn(
        'Global version "$version" could not be parsed: $e. '
        'The global symlink may be corrupted.',
      );

      return null;
    }
  }

  bool isGlobal(CacheFlutterVersion version) {
    if (!_globalCacheLink.existsSync()) {
      return false;
    }

    try {
      return _globalCacheLink.targetSync() == version.directory;
    } on FileSystemException catch (e) {
      logger.debug('Cannot verify if version is global: $e');

      return false;
    }
  }

  /// Returns the global version name, or null if none is set.
  String? getGlobalVersion() {
    if (!_globalCacheLink.existsSync()) return null;

    String targetPath;
    try {
      targetPath = _globalCacheLink.targetSync();
    } on FileSystemException catch (e) {
      logger.warn('Failed to resolve global symlink: $e');

      return null;
    }

    final relative = _relativeVersionNameFromCachePath(targetPath);
    if (relative != null) return relative;

    // Symlink points outside the cache directory; fall back to the directory
    // name, which loses fork information.
    logger.debug(
      'Global symlink target "$targetPath" could not be resolved relative '
      'to the cache directory. Fork information may not be preserved.',
    );

    return path.basename(path.normalize(targetPath));
  }

  /// Renames [version]'s cache directory to match its actual SDK version.
  void moveToSdkVersionDirectory(CacheFlutterVersion version) {
    final sdkVersion = version.flutterSdkVersion;
    if (sdkVersion == null) {
      throw AppException(
        'Cannot move to SDK version directory without a valid version',
      );
    }

    final versionDir = Directory(version.directory);
    if (!versionDir.existsSync()) return;

    final versionString =
        version.fromFork ? '${version.fork}/$sdkVersion' : sdkVersion;
    final targetVersion = FlutterVersion.parse(versionString);
    final newDir = getVersionCacheDir(targetVersion);

    if (newDir.existsSync()) {
      newDir.deleteSync(recursive: true);
    }

    // renameSync requires the parent directory to exist
    if (targetVersion.fromFork) {
      final forkDir = Directory(
        path.join(context.versionsCachePath, targetVersion.fork!),
      );
      if (!forkDir.existsSync()) {
        forkDir.createSync(recursive: true);
      }
    }

    versionDir.renameSync(newDir.path);
  }

  /// Determines if [configured] and [cached] versions should be considered
  /// matching.
  ///
  /// Matching rules:
  /// 1. Exact string match (after normalizing leading 'v'/'V' prefix)
  /// 2. If either has build metadata (+xxx), both must match exactly
  /// 3. If both have pre-release identifiers (-xxx), both must match exactly
  /// 4. If [configured] has pre-release but [cached] does not, match on
  ///    `major.minor.patch` (allows dev builds to match stable SDKs)
  /// 5. If [cached] has pre-release but [configured] does not, require exact match
  /// 6. For non-semver versions (e.g., git refs), catches [FormatException] and
  ///    falls back to normalized string equality with a warning logged
  ///
  /// This handles Flutter SDK naming where the cached SDK may strip pre-release
  /// suffixes from the configured version.
  @visibleForTesting
  bool versionsMatch(String configured, String cached) {
    if (configured == cached) return true;

    final normConfigured = _normalizeVersion(configured);
    final normCached = _normalizeVersion(cached);

    if (normConfigured == normCached) return true;

    try {
      final configVer = Version.parse(normConfigured);
      final cachedVer = Version.parse(normCached);

      if (configVer.build.isNotEmpty || cachedVer.build.isNotEmpty) {
        return configVer == cachedVer;
      }

      if (configVer.preRelease.isNotEmpty && cachedVer.preRelease.isNotEmpty) {
        return configVer == cachedVer;
      }

      if (configVer.preRelease.isNotEmpty && cachedVer.preRelease.isEmpty) {
        return configVer.major == cachedVer.major &&
            configVer.minor == cachedVer.minor &&
            configVer.patch == cachedVer.patch;
      }

      // Remaining case: configured has no pre-release but cached does;
      // require exact match (which will fail because of differing pre-release).
      return configVer == cachedVer;
    } on FormatException catch (e) {
      logger.warn(
        'Unable to parse versions as semantic versions: '
        'configured="$configured", cached="$cached". '
        'Falling back to string comparison. Error: $e',
      );

      return normConfigured == normCached;
    }
  }
}
