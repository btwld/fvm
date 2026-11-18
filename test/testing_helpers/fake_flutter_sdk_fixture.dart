import 'dart:convert';
import 'dart:io';

import 'package:fvm/fvm.dart';
import 'package:path/path.dart' as p;

import 'fixture_paths.dart';

/// Layout state for a fake Flutter SDK directory in the test cache.
enum FakeFlutterSdkState {
  /// Installed clone with executables only.
  ///
  /// No SDK version metadata is written, matching a pre-setup cache entry where
  /// FVM should not infer metadata from surrounding git tags.
  installedNotSetup,

  /// Fully set up SDK with JSON metadata and Dart SDK cache files.
  installedSetup,

  /// Setup SDK where JSON and legacy `version` disagree (JSON wins).
  versionMismatch,

  /// Installed SDK missing the Flutter executable.
  invalidExecutable,
}

/// Recorded metadata used to generate fake SDK directories.
class FlutterRootVersionFixture {
  const FlutterRootVersionFixture({
    required this.name,
    required this.legacyVersion,
    required this.dartSdkVersion,
    required this.flutterVersionJson,
    this.mismatchLegacyVersion,
    this.mismatchJsonVersion,
  });

  final String name;
  final String legacyVersion;
  final String dartSdkVersion;
  final Map<String, dynamic> flutterVersionJson;
  final String? mismatchLegacyVersion;
  final String? mismatchJsonVersion;

  String get primaryFlutterVersion {
    final jsonVersion = flutterVersionJson['flutterVersion'] as String?;
    if (jsonVersion != null && jsonVersion.isNotEmpty) return jsonVersion;

    final frameworkVersion = flutterVersionJson['frameworkVersion'] as String?;
    if (frameworkVersion != null && frameworkVersion.isNotEmpty) {
      return frameworkVersion;
    }

    return legacyVersion;
  }

  static FlutterRootVersionFixture fromJson(Map<String, dynamic> json) {
    final flutterVersionJson = Map<String, dynamic>.from(
      json['flutterVersionJson'] as Map,
    );

    return FlutterRootVersionFixture(
      name: json['name'] as String,
      legacyVersion: json['legacyVersion'] as String,
      dartSdkVersion: json['dartSdkVersion'] as String,
      flutterVersionJson: flutterVersionJson,
      mismatchLegacyVersion: json['mismatchLegacyVersion'] as String?,
      mismatchJsonVersion: json['mismatchJsonVersion'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'legacyVersion': legacyVersion,
      'dartSdkVersion': dartSdkVersion,
      'flutterVersionJson': _sortedJsonMap(flutterVersionJson),
      if (mismatchLegacyVersion != null)
        'mismatchLegacyVersion': mismatchLegacyVersion,
      if (mismatchJsonVersion != null)
        'mismatchJsonVersion': mismatchJsonVersion,
    };
  }
}

/// Writes a minimal Flutter SDK layout into the test cache directory.
class FakeFlutterSdkFixture {
  const FakeFlutterSdkFixture._();

  static const _fixturesRoot = 'test/fixtures/flutter_root_versions';

  static CacheFlutterVersion install(
    FvmContext context,
    FlutterVersion version, {
    FakeFlutterSdkState state = FakeFlutterSdkState.installedNotSetup,
    String? fixtureName,
    String? mismatchCachedVersion,
  }) {
    final cacheService = context.get<CacheService>();
    final versionDir = cacheService.getVersionCacheDir(version);
    final fixture = loadFixture(fixtureName ?? resolveFixtureName(version));

    if (version.fromFork) {
      Directory(
        p.join(context.versionsCachePath, version.fork!),
      ).createSync(recursive: true);
    }

    versionDir.createSync(recursive: true);
    Directory(p.join(versionDir.path, '.git')).createSync();

    final origin = version.fromFork
        ? context.config.forks
            .where((fork) => fork.name == version.fork)
            .firstOrNull
            ?.url
        : context.flutterUrl;
    if (origin != null) {
      File(p.join(versionDir.path, '.git', 'config')).writeAsStringSync(
        '[remote "origin"]\n\turl = $origin\n',
      );
    }

    final legacyVersion = _legacyVersionForState(fixture, state);

    if (_writesLegacyVersionFile(state)) {
      File(p.join(versionDir.path, 'version')).writeAsStringSync(legacyVersion);
    }

    if (state != FakeFlutterSdkState.invalidExecutable) {
      _writeExecutable(p.join(versionDir.path, 'bin', flutterExecFileName));
      _writeExecutable(p.join(versionDir.path, 'bin', dartExecFileName));
    }

    if (_writesSetupFiles(state)) {
      final jsonVersion = _jsonVersionForState(
        fixture,
        state,
        mismatchCachedVersion: mismatchCachedVersion,
      );

      _writeFlutterVersionJson(
        versionDir,
        fixture: fixture,
        flutterVersion: jsonVersion,
      );

      final dartVersionFile = File(
        p.join(versionDir.path, 'bin', 'cache', 'dart-sdk', 'version'),
      )..createSync(recursive: true);
      dartVersionFile.writeAsStringSync(fixture.dartSdkVersion);

      _writeExecutable(
        p.join(
          versionDir.path,
          'bin',
          'cache',
          'dart-sdk',
          'bin',
          dartExecFileName,
        ),
      );
    }

    return CacheFlutterVersion.fromVersion(version, directory: versionDir.path);
  }

  static FlutterRootVersionFixture loadFixture(String name) {
    final file = File(packageFixturePath(p.join(_fixturesRoot, '$name.json')));
    if (!file.existsSync()) {
      throw StateError('Missing flutter root fixture: ${file.path}');
    }

    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    return FlutterRootVersionFixture.fromJson(decoded);
  }

  static String resolveFixtureName(FlutterVersion version) {
    if (version.isChannel) {
      return switch (version.name) {
        'stable' => 'stable_3_10_5',
        'beta' => 'beta_3_19_0',
        _ => 'stable_3_10_5',
      };
    }

    final normalized = version.version.startsWith('v')
        ? version.version.substring(1)
        : version.version;

    return switch (normalized) {
      '3.10.0' => 'stable_3_10_0',
      '3.10.5' => 'stable_3_10_5',
      '3.19.0' => version.releaseChannel == FlutterChannel.beta
          ? 'beta_3_19_0'
          : 'stable_3_10_5',
      '3.19.0@beta' => 'beta_3_19_0',
      _ => 'stable_3_10_0',
    };
  }

  static String fixturePath(String name) =>
      packageFixturePath(p.join(_fixturesRoot, '$name.json'));

  static bool _writesSetupFiles(FakeFlutterSdkState state) {
    return state == FakeFlutterSdkState.installedSetup ||
        state == FakeFlutterSdkState.versionMismatch;
  }

  static bool _writesLegacyVersionFile(FakeFlutterSdkState state) {
    return state != FakeFlutterSdkState.installedNotSetup;
  }

  static String _legacyVersionForState(
    FlutterRootVersionFixture fixture,
    FakeFlutterSdkState state,
  ) {
    if (state == FakeFlutterSdkState.versionMismatch) {
      return fixture.mismatchLegacyVersion ?? fixture.legacyVersion;
    }

    return fixture.legacyVersion;
  }

  static String _jsonVersionForState(
    FlutterRootVersionFixture fixture,
    FakeFlutterSdkState state, {
    String? mismatchCachedVersion,
  }) {
    if (state == FakeFlutterSdkState.versionMismatch) {
      return mismatchCachedVersion ??
          fixture.mismatchJsonVersion ??
          fixture.primaryFlutterVersion;
    }

    return fixture.primaryFlutterVersion;
  }

  static void _writeFlutterVersionJson(
    Directory versionDir, {
    required FlutterRootVersionFixture fixture,
    required String flutterVersion,
  }) {
    final file = File(
      p.join(versionDir.path, 'bin', 'cache', 'flutter.version.json'),
    )..createSync(recursive: true);

    final payload = <String, dynamic>{
      ...fixture.flutterVersionJson,
      'frameworkVersion': flutterVersion,
      'flutterVersion': flutterVersion,
    };

    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(_sortedJsonMap(payload)),
    );
  }

  static void _writeExecutable(String path) {
    final file = File(path)..createSync(recursive: true);

    if (Platform.isWindows) {
      file.writeAsStringSync('@echo off\r\nexit /b 0\r\n');
      return;
    }

    file.writeAsStringSync('#!/bin/sh\nexit 0\n');
    Process.runSync('chmod', ['755', path]);
  }
}

Map<String, dynamic> _sortedJsonMap(Map<String, dynamic> source) {
  final keys = source.keys.toList()..sort();
  return {for (final key in keys) key: source[key]};
}
