import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

const _semverPattern =
    r'\d+\.\d+\.\d+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?';

final _versionLineRe = RegExp(
  '^(?:fvm(?:\\s+version)?\\s*:?\\s*)?v?($_semverPattern)\\s*\$',
  caseSensitive: false,
);
final _versionInlineRe = RegExp(
  '(?:^|[^0-9A-Za-z])(?:fvm(?:\\s+version)?\\s*:?\\s*)?v?($_semverPattern)(?=\$|[^0-9A-Za-z])',
  caseSensitive: false,
);

final _jsonApiMin = Version(3, 1, 2);
final _skipInputMin = Version(3, 2, 0);

class FvmVersion {
  final Version? semver;
  final String raw;

  const FvmVersion._({required this.semver, required this.raw});

  const FvmVersion.unknown([this.raw = 'unknown']) : semver = null;

  factory FvmVersion.fromSemver(Version semver) =>
      FvmVersion._(semver: semver, raw: semver.toString());

  bool _isAtLeast(Version min) => semver != null && semver! >= min;

  int get major => semver?.major ?? 0;
  int get minor => semver?.minor ?? 0;
  int get patch => semver?.patch ?? 0;

  bool get isUnknown => semver == null;

  bool get supportsJsonApi => _isAtLeast(_jsonApiMin);
  bool get supportsSkipInput => _isAtLeast(_skipInputMin);

  @override
  String toString() => raw;
}

String _asText(Object? value) {
  if (value is String) return value;
  if (value is List<int>) return String.fromCharCodes(value);

  return '$value';
}

Version? _parseSemver(String value) {
  try {
    return Version.parse(value);
  } on FormatException {
    return null;
  }
}

FvmVersion parseFvmVersionOutput(String output) {
  final text = output.trim();
  if (text.isEmpty) return const FvmVersion.unknown();

  final lines = text.split('\n').map((line) => line.trim()).toList();

  // Prefer clean lines first (e.g., `4.0.5` or `fvm 4.0.5`).
  for (final line in lines) {
    if (line.isEmpty) continue;

    final match = _versionLineRe.firstMatch(line);
    if (match != null) {
      final version = _parseSemver(match.group(1)!);
      if (version != null) {
        return FvmVersion.fromSemver(version);
      }
    }
  }

  // Then prefer inline matches on lines that explicitly mention FVM.
  for (final line in lines) {
    if (line.isEmpty || !line.toLowerCase().contains('fvm')) continue;

    final match = _versionInlineRe.firstMatch(line);
    if (match != null) {
      final version = _parseSemver(match.group(1)!);
      if (version != null) {
        return FvmVersion.fromSemver(version);
      }
    }
  }

  return const FvmVersion.unknown();
}

String resolveFvmExecutable() {
  if (!Platform.isWindows) return 'fvm';
  for (final directory in (Platform.environment['PATH'] ?? '').split(';')) {
    if (!File(directory).isAbsolute) continue;
    final exe = File('$directory/fvm.exe');
    if (exe.existsSync()) return exe.path;
  }
  throw StateError(
    'Install the native fvm.exe on PATH for the Windows MCP server.',
  );
}

Future<FvmVersion> detectFvmVersion() async {
  try {
    final res = await Process.run(resolveFvmExecutable(), ['--version']);
    if (res.exitCode != 0) {
      return const FvmVersion.unknown();
    }
    final combined = '${_asText(res.stdout)}\n${_asText(res.stderr)}';

    return parseFvmVersionOutput(combined);
  } catch (_) {
    return const FvmVersion.unknown();
  }
}
