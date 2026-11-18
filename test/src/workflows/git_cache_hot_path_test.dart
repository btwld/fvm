import 'dart:io';

import 'package:fvm/fvm.dart';
import 'package:path/path.dart' as p;
import 'package:fvm/src/services/flutter_service.dart';
import 'package:fvm/src/services/git_service.dart';
import 'package:fvm/src/workflows/ensure_cache.workflow.dart';
import 'package:fvm/src/workflows/run_configured_flutter.workflow.dart';
import 'package:test/test.dart';

import '../../testing_utils.dart';

void main() {
  group('Git cache command hot path', () {
    test('rejects SDKs from another origin even with force enabled', () async {
      final context = TestFactory.fastContext();
      final version = FlutterVersion.parse('stable');
      final installed = FakeFlutterSdkFixture.install(context, version);
      File(p.join(installed.directory, '.git', 'config')).writeAsStringSync(
          '[remote "origin"]\nurl = https://example.invalid/alternate.git\n');
      await expectLater(
          EnsureCacheWorkflow(context)(version,
              force: true, maintainGitCacheOnHit: false),
          throwsA(isA<AppException>()));
      expect(Directory(installed.directory).existsSync(), isTrue);
    });

    test('cache lookup rejects linked ancestors before repair', () {
      final context = TestFactory.fastContext();
      final external = createTempDir('separate-sdk-directory');
      Directory(context.versionsCachePath).createSync(recursive: true);
      Link(p.join(context.versionsCachePath, 'fork')).createSync(external.path);
      expect(
          () => context
              .get<CacheService>()
              .getVersionCacheDir(FlutterVersion.parse('fork/stable')),
          throwsA(isA<AppException>()));
    }, skip: Platform.isWindows);

    test('installed SDK skips shared git cache maintenance', () async {
      final context = TestFactory.fastContext();
      final version = FlutterVersion.parse('3.10.0');
      FakeFlutterSdkFixture.install(
        context,
        version,
        state: FakeFlutterSdkState.installedSetup,
      );

      final gitService = context.get<GitService>() as FakeGitService;
      final result = await EnsureCacheWorkflow(context).call(
        version,
        maintainGitCacheOnHit: false,
      );

      expect(result.name, version.name);
      expect(gitService.ensureBareCacheCalls, 0);
      expect(gitService.updateLocalMirrorCalls, 0);
    });

    test('cache miss still prepares the git cache before install', () async {
      final context = TestFactory.fastContext();
      final version = FlutterVersion.parse('3.10.0');
      final gitService = context.get<GitService>() as FakeGitService;
      final flutterService =
          context.get<FlutterService>() as FakeFlutterService;

      final result = await EnsureCacheWorkflow(context).call(
        version,
        shouldInstall: true,
        maintainGitCacheOnHit: false,
      );

      expect(result.name, version.name);
      expect(gitService.ensureBareCacheCalls, 1);
      expect(gitService.updateLocalMirrorCalls, 1);
      expect(flutterService.installUseGitCacheValues, equals([true]));
    });

    group('configured execution', () {
      test('project flutter and dart commands skip shared cache', () async {
        final version = FlutterVersion.parse('3.10.0');
        final context = _projectContextWithInstalledSdk(
          version,
          tempPrefix: 'git_cache_project_hot_path',
        );
        final workflow = RunConfiguredFlutterWorkflow(context);

        final flutterResult = await workflow.call(
          'flutter',
          args: ['--version'],
        );
        final dartResult = await workflow.call(
          'dart',
          args: ['--version'],
        );

        expect(flutterResult.exitCode, 0);
        expect(dartResult.exitCode, 0);
        _expectNoSharedGitCacheMaintenance(context, ['flutter', 'dart']);
      });

      test('global flutter and dart commands skip shared cache', () async {
        final context = TestFactory.fastContext();
        final version = FlutterVersion.parse('3.10.0');
        final cachedVersion = FakeFlutterSdkFixture.install(
          context,
          version,
          state: FakeFlutterSdkState.installedSetup,
        );
        context.get<CacheService>().setGlobal(cachedVersion);

        final workflow = RunConfiguredFlutterWorkflow(context);

        final flutterResult = await workflow.call(
          'flutter',
          args: ['--version'],
        );
        final dartResult = await workflow.call(
          'dart',
          args: ['--version'],
        );

        expect(flutterResult.exitCode, 0);
        expect(dartResult.exitCode, 0);
        _expectNoSharedGitCacheMaintenance(context, ['flutter', 'dart']);
      });

      test('exec command skips shared cache maintenance', () async {
        final version = FlutterVersion.parse('3.10.0');
        final context = _projectContextWithInstalledSdk(
          version,
          tempPrefix: 'git_cache_exec_hot_path',
        );

        final runner = TestCommandRunner(context);

        final exitCode = await runner.run([
          'fvm',
          'exec',
          'flutter',
          '--version',
        ]);

        expect(exitCode, 0);
        _expectNoSharedGitCacheMaintenance(context, ['flutter']);
      });
    });
  });
}

FvmContext _projectContextWithInstalledSdk(
  FlutterVersion version, {
  required String tempPrefix,
}) {
  final projectDir = createTempDir(tempPrefix);
  createProjectConfig(ProjectConfig(flutter: version.name), projectDir);
  final context = TestFactory.fastContext(
    workingDirectoryOverride: projectDir.path,
  );
  FakeFlutterSdkFixture.install(
    context,
    version,
    state: FakeFlutterSdkState.installedSetup,
  );

  return context;
}

void _expectNoSharedGitCacheMaintenance(
  FvmContext context,
  List<String> expectedCommands,
) {
  final gitService = context.get<GitService>() as FakeGitService;
  final flutterService = context.get<FlutterService>() as FakeFlutterService;

  expect(gitService.ensureBareCacheCalls, 0);
  expect(gitService.updateLocalMirrorCalls, 0);
  expect(
    flutterService.runCalls.map((call) => call.cmd),
    equals(expectedCommands),
  );
}
