import 'dart:convert';
import 'dart:io';

import 'package:fvm/src/api/models/json_response.dart';
import 'package:fvm/src/models/flutter_version_model.dart';
import 'package:fvm/src/models/project_model.dart';
import 'package:fvm/src/services/cache_service.dart';
import 'package:fvm/src/services/logger_service.dart';
import 'package:fvm/src/services/project_registry_service.dart';
import 'package:io/io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../testing_utils.dart';

void main() {
  String plainOutput(Logger logger) {
    return logger.outputs.join('\n').replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');
  }

  /// Matches the Projects cell, not the explanatory line below the table.
  final unusedCell = matches(RegExp(r'\u2502\s*Unused\s*\u2502'));

  group('fvm list', () {
    test('shows the latest release for an outdated channel SDK', () async {
      final context = TestFactory.fastContext();
      FakeFlutterSdkFixture.install(
        context,
        FlutterVersion.parse('stable'),
        state: FakeFlutterSdkState.installedSetup,
        fixtureName: 'stable_3_10_0',
      );
      final runner = TestFactory.fastCommandRunner(context: context);

      expect(await runner.run(['fvm', 'list']), ExitCode.success.code);
      expect(plainOutput(context.get<Logger>()), contains('3.10.0 → 3.10.5'));
    });

    test('omits channel updates for current, pinned, main and forked SDKs',
        () async {
      final context = TestFactory.fastContext();
      const versions = ['stable', '3.10.0', 'main', 'master', 'myfork/stable'];
      for (final name in versions) {
        FakeFlutterSdkFixture.install(
          context,
          FlutterVersion.parse(name),
          state: FakeFlutterSdkState.installedSetup,
          fixtureName: name == 'stable' ? 'stable_3_10_5' : 'stable_3_10_0',
        );
      }
      final runner = TestFactory.fastCommandRunner(context: context);

      expect(await runner.run(['fvm', 'list']), ExitCode.success.code);
      final output = plainOutput(context.get<Logger>());
      for (final name in versions) {
        expect(output, contains(name));
      }
      expect(output, isNot(contains('→')));
    });

    test('marks cached versions no known project pins as unused', () async {
      final projectDir = createConfiguredProject(name: 'local');
      final context = TestFactory.fastContext(
        workingDirectoryOverride: projectDir.path,
      );
      FakeFlutterSdkFixture.install(context, FlutterVersion.parse('stable'));
      FakeFlutterSdkFixture.install(context, FlutterVersion.parse('beta'));
      context.get<ProjectRegistryService>().track(
            Project.loadFromDirectory(projectDir),
          );
      expect(File(context.projectsRegistryPath).existsSync(), isTrue);
      final runner = TestFactory.fastCommandRunner(context: context);

      final exitCode = await runner.run(['fvm', 'list']);

      expect(exitCode, ExitCode.success.code);
      final output = plainOutput(context.get<Logger>());
      expect(output, unusedCell);
      expect(output, contains('no project known to FVM pins that SDK'));
      expect(output, contains('fvm cleanup'));
    });

    test('marks a forked channel-qualified SDK as local and in use', () async {
      final projectDir = createConfiguredProject(
        name: 'forked',
        flutter: 'myfork/3.10.0@beta',
      );
      final context = TestFactory.fastContext(
        workingDirectoryOverride: projectDir.path,
      );
      FakeFlutterSdkFixture.install(
        context,
        FlutterVersion.parse('myfork/3.10.0@beta'),
      );
      final runner = TestFactory.fastCommandRunner(context: context);

      expect(await runner.run(['fvm', 'list']), ExitCode.success.code);

      final output = plainOutput(context.get<Logger>());
      expect(
        output,
        matches(
          RegExp(
            r'\u2502\s*myfork/3\.10\.0\s*\u2502[^\n]*'
            r'\u2502\s*\u25cf\s*\u2502\s*1\s*\u2502',
          ),
        ),
      );
    });

    test('does not call the global version unused', () async {
      final context = TestFactory.fastContext();
      FakeFlutterSdkFixture.install(context, FlutterVersion.parse('stable'));
      final cache = context.get<CacheService>();
      cache.setGlobal(cache.getVersion(FlutterVersion.parse('stable'))!);
      final runner = TestFactory.fastCommandRunner(context: context);

      expect(await runner.run(['fvm', 'list']), ExitCode.success.code);
      expect(plainOutput(context.get<Logger>()), isNot(unusedCell));
    });

    test('still lists versions when the registry is malformed', () async {
      final context = TestFactory.fastContext();
      FakeFlutterSdkFixture.install(context, FlutterVersion.parse('stable'));
      File(context.projectsRegistryPath)
        ..createSync(recursive: true)
        ..writeAsStringSync('not-json');
      final runner = TestFactory.fastCommandRunner(context: context);

      final exitCode = await runner.run(['fvm', 'list']);

      expect(exitCode, ExitCode.success.code);
      expect(
        File(context.projectsRegistryPath).readAsStringSync(),
        'not-json',
      );
      final output = plainOutput(context.get<Logger>());
      expect(output, contains(context.projectsRegistryPath));
      expect(output, isNot(unusedCell));
    });

    test('still lists versions when the local pin resolves outside the cache',
        () async {
      final projectDir = createConfiguredProject(
        name: 'unsafe_pin',
        flutter: '../evil',
      );
      final context = TestFactory.fastContext(
        workingDirectoryOverride: projectDir.path,
      );
      FakeFlutterSdkFixture.install(context, FlutterVersion.parse('stable'));
      final runner = TestFactory.fastCommandRunner(context: context);

      final exitCode = await runner.run(['fvm', 'list']);

      expect(exitCode, ExitCode.success.code);
      expect(plainOutput(context.get<Logger>()), unusedCell);
      expect(
        plainOutput(context.get<Logger>()),
        contains('configured but not cached'),
      );
    });

    test('explains when no local project version is configured', () async {
      final context = TestFactory.fastContext();
      FakeFlutterSdkFixture.install(context, FlutterVersion.parse('stable'));
      final runner = TestFactory.fastCommandRunner(context: context);

      expect(await runner.run(['fvm', 'list']), ExitCode.success.code);

      expect(
        plainOutput(context.get<Logger>()),
        contains('none is configured here'),
      );
    });
  });

  group('fvm api list', () {
    test('reports recorded projects and unreferenced versions', () async {
      final projectDir = createConfiguredProject(name: 'api_app');
      final context = TestFactory.fastContext();
      FakeFlutterSdkFixture.install(context, FlutterVersion.parse('stable'));
      FakeFlutterSdkFixture.install(context, FlutterVersion.parse('3.10.0'));
      context.get<ProjectRegistryService>().track(
            Project.loadFromDirectory(projectDir),
          );
      final runner = TestFactory.fastCommandRunner(context: context);

      final printed = await runnerZoned(runner, [
        'fvm',
        'api',
        'list',
        '--compress',
      ]);

      final response = GetCacheVersionsResponse.fromJson(printed.join());
      expect(response.projects, [projectDir.resolveSymbolicLinksSync()]);
      expect(response.unreferencedVersions, ['3.10.0']);
    });

    test(
      'counts an untracked configured project so its SDK is not unreferenced',
      () async {
        final projectDir = createConfiguredProject(name: 'fresh_clone');
        final context = TestFactory.fastContext(
          workingDirectoryOverride: projectDir.path,
        );
        FakeFlutterSdkFixture.install(context, FlutterVersion.parse('stable'));
        FakeFlutterSdkFixture.install(context, FlutterVersion.parse('beta'));
        expect(File(context.projectsRegistryPath).existsSync(), isFalse);
        final runner = TestFactory.fastCommandRunner(context: context);

        final printed = await runnerZoned(runner, [
          'fvm',
          'api',
          'list',
          '--compress',
        ]);

        final response = GetCacheVersionsResponse.fromJson(printed.join());
        expect(response.projects, [projectDir.resolveSymbolicLinksSync()]);
        expect(response.unreferencedVersions, ['beta']);
        expect(File(context.projectsRegistryPath).existsSync(), isFalse);
      },
    );

    test('does not list the global version as unreferenced', () async {
      final context = TestFactory.fastContext();
      FakeFlutterSdkFixture.install(context, FlutterVersion.parse('stable'));
      final cache = context.get<CacheService>();
      cache.setGlobal(cache.getVersion(FlutterVersion.parse('stable'))!);
      final runner = TestFactory.fastCommandRunner(context: context);

      final printed = await runnerZoned(runner, [
        'fvm',
        'api',
        'list',
        '--compress',
      ]);

      final response = GetCacheVersionsResponse.fromJson(printed.join());
      expect(response.unreferencedVersions, isEmpty);
    });

    test('fails on a malformed registry without rewriting it', () async {
      final context = TestFactory.fastContext();
      File(context.projectsRegistryPath)
        ..createSync(recursive: true)
        ..writeAsStringSync('not-json');
      final runner = TestFactory.fastCommandRunner(context: context);

      final exitCode = await runner.run(['fvm', 'api', 'list']);

      expect(exitCode, isNot(ExitCode.success.code));
      expect(
        File(context.projectsRegistryPath).readAsStringSync(),
        'not-json',
      );
    });

    test('returns empty arrays when nothing is recorded', () async {
      final context = TestFactory.fastContext();
      final runner = TestFactory.fastCommandRunner(context: context);

      final printed = await runnerZoned(runner, [
        'fvm',
        'api',
        'list',
        '--compress',
      ]);

      final decoded = jsonDecode(printed.join()) as Map<String, dynamic>;
      expect(decoded['projects'], isEmpty);
      expect(decoded['unreferencedVersions'], isEmpty);
    });

    test('ignores malformed current project metadata', () async {
      final projectDir = createTempDir('malformed_api_project');
      File(p.join(projectDir.path, 'pubspec.yaml'))
          .writeAsStringSync('name: [');
      final context = TestFactory.fastContext(
        workingDirectoryOverride: projectDir.path,
      );
      FakeFlutterSdkFixture.install(context, FlutterVersion.parse('stable'));
      final runner = TestFactory.fastCommandRunner(context: context);

      final printed = await runnerZoned(runner, [
        'fvm',
        'api',
        'list',
        '--compress',
      ]);

      final response = GetCacheVersionsResponse.fromJson(printed.join());
      expect(response.projects, isEmpty);
      expect(response.unreferencedVersions, ['stable']);
    });
  });

  group('fvm api cleanup', () {
    test('returns structured cached patch upgrades', () async {
      final projectDir = createConfiguredProject(
        name: 'upgrade_api',
        flutter: '3.10.0',
      );
      final context = TestFactory.fastContext();
      FakeFlutterSdkFixture.install(
        context,
        FlutterVersion.parse('3.10.0'),
      );
      FakeFlutterSdkFixture.install(
        context,
        FlutterVersion.parse('3.10.5'),
      );
      context.get<ProjectRegistryService>().track(
            Project.loadFromDirectory(projectDir),
          );
      final runner = TestFactory.fastCommandRunner(context: context);

      final printed = await runnerZoned(runner, [
        'fvm',
        'api',
        'cleanup',
        '--compress',
      ]);

      final response = GetCleanupResponse.fromJson(printed.join());
      final upgrade = response.upgrades.singleWhere(
        (item) => item.fromVersion == '3.10.0',
      );
      expect(upgrade.toVersion, '3.10.5');
      expect(
        upgrade.actions.single.workingDirectory,
        projectDir.resolveSymbolicLinksSync(),
      );
      expect(response.unused, contains('3.10.5'));
      expect(response.removable, isNot(contains('3.10.5')));
    });

    test('unused matches api list unreferencedVersions', () async {
      final projectDir = createConfiguredProject(
        name: 'same_unused',
        flutter: '3.10.0',
      );
      final context = TestFactory.fastContext();
      FakeFlutterSdkFixture.install(context, FlutterVersion.parse('3.10.0'));
      FakeFlutterSdkFixture.install(context, FlutterVersion.parse('3.10.5'));
      FakeFlutterSdkFixture.install(context, FlutterVersion.parse('beta'));
      context.get<ProjectRegistryService>().track(
            Project.loadFromDirectory(projectDir),
          );
      final runner = TestFactory.fastCommandRunner(context: context);

      final listPrinted = await runnerZoned(runner, [
        'fvm',
        'api',
        'list',
        '--compress',
        '--skip-size-calculation',
      ]);
      final cleanupPrinted = await runnerZoned(runner, [
        'fvm',
        'api',
        'cleanup',
        '--compress',
      ]);

      final list = GetCacheVersionsResponse.fromJson(listPrinted.join());
      final cleanup = GetCleanupResponse.fromJson(cleanupPrinted.join());
      expect(cleanup.unused, list.unreferencedVersions);
      expect(cleanup.unused, containsAll(['3.10.5', 'beta']));
      expect(cleanup.removable, ['beta']);
    });

    test('lists unused SDK names', () async {
      final context = TestFactory.fastContext();
      FakeFlutterSdkFixture.install(context, FlutterVersion.parse('stable'));
      FakeFlutterSdkFixture.install(context, FlutterVersion.parse('beta'));
      final runner = TestFactory.fastCommandRunner(context: context);

      final printed = await runnerZoned(runner, [
        'fvm',
        'api',
        'cleanup',
        '--compress',
      ]);

      final response = GetCleanupResponse.fromJson(printed.join());
      expect(response.upgrades, isEmpty);
      expect(response.unused, ['beta', 'stable']);
      expect(response.removable, ['beta', 'stable']);
    });

    test('fails on a malformed registry without rewriting it', () async {
      final context = TestFactory.fastContext();
      File(context.projectsRegistryPath)
        ..createSync(recursive: true)
        ..writeAsStringSync('not-json');
      final runner = TestFactory.fastCommandRunner(context: context);

      final exitCode = await runner.run(['fvm', 'api', 'cleanup']);

      expect(exitCode, isNot(ExitCode.success.code));
      expect(
        File(context.projectsRegistryPath).readAsStringSync(),
        'not-json',
      );
    });
  });
}
