@Tags(['git'])
import 'dart:convert';
import 'dart:io';

import 'package:fvm/src/models/cache_flutter_version_model.dart';
import 'package:fvm/src/models/config_model.dart';
import 'package:fvm/src/models/flutter_version_model.dart';
import 'package:fvm/src/services/cache_service.dart';
import 'package:fvm/src/services/flutter_service.dart';
import 'package:fvm/src/services/git_service.dart';
import 'package:fvm/src/services/logger_service.dart';
import 'package:fvm/src/services/process_service.dart';
import 'package:fvm/src/utils/constants.dart';
import 'package:fvm/src/utils/context.dart';
import 'package:fvm/src/utils/exceptions.dart';
import 'package:fvm/src/workflows/ensure_cache.workflow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../testing_utils.dart';

Future<void> _deleteLooseGitObject({
  required String repoPath,
  required String objectSha,
}) async {
  final objectFile = File(
    p.join(
      repoPath,
      'objects',
      objectSha.substring(0, 2),
      objectSha.substring(2),
    ),
  );

  if (!objectFile.existsSync()) {
    final packDir = Directory(p.join(repoPath, 'objects', 'pack'));
    if (packDir.existsSync()) {
      final packFiles = packDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.pack'))
          .toList();

      for (final pack in packFiles) {
        final process = await Process.start(
          'git',
          ['unpack-objects'],
          workingDirectory: repoPath,
          runInShell: true,
        );
        await pack.openRead().pipe(process.stdin);
        final exitCode = await process.exitCode;
        if (exitCode != 0) {
          throw Exception('Failed to unpack git objects from ${pack.path}');
        }
      }
    }
  }

  if (!objectFile.existsSync()) {
    throw Exception('Expected loose git object at ${objectFile.path}');
  }

  if (Platform.isWindows) {
    await Process.run('attrib', ['-R', objectFile.path], runInShell: true);
  }

  final attempts = Platform.isWindows ? 3 : 1;
  for (var attempt = 1; attempt <= attempts; attempt++) {
    try {
      objectFile.deleteSync();
      return;
    } on FileSystemException {
      if (!Platform.isWindows || attempt == attempts) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
    }
  }
}

Future<String> _commitToRemoteBranch({
  required Directory root,
  required Directory remoteDir,
  required String fileName,
  String branch = 'master',
}) async {
  final workDir = Directory(p.join(root.path, '${fileName}_work'))
    ..createSync();
  try {
    await runGitCommand(['clone', remoteDir.path, workDir.path]);
    await runGitCommand(
      ['config', 'user.email', 'tests@fvm.app'],
      workingDirectory: workDir.path,
    );
    await runGitCommand(
      ['config', 'user.name', 'FVM Tests'],
      workingDirectory: workDir.path,
    );
    await runGitCommand(['checkout', branch], workingDirectory: workDir.path);
    File(p.join(workDir.path, fileName)).writeAsStringSync(fileName);
    await runGitCommand(['add', '.'], workingDirectory: workDir.path);
    await runGitCommand(
      ['commit', '-m', 'Add $fileName'],
      workingDirectory: workDir.path,
    );
    final shaResult = await runGitCommand(
      ['rev-parse', 'HEAD'],
      workingDirectory: workDir.path,
    );
    await runGitCommand(
      ['push', 'origin', 'HEAD:$branch'],
      workingDirectory: workDir.path,
    );

    return shaResult.stdout.toString().trim();
  } finally {
    if (workDir.existsSync()) {
      workDir.deleteSync(recursive: true);
    }
  }
}

Future<String> _pushPrOnlyCommit({
  required Directory root,
  required Directory remoteDir,
}) async {
  final workDir = Directory(p.join(root.path, 'pr_only_work'))..createSync();
  try {
    await runGitCommand(['clone', remoteDir.path, workDir.path]);
    await runGitCommand(
      ['config', 'user.email', 'tests@fvm.app'],
      workingDirectory: workDir.path,
    );
    await runGitCommand(
      ['config', 'user.name', 'FVM Tests'],
      workingDirectory: workDir.path,
    );
    await runGitCommand(
      ['checkout', '-b', 'pr-only'],
      workingDirectory: workDir.path,
    );
    File(p.join(workDir.path, 'PR_ONLY.md')).writeAsStringSync('pr only');
    await runGitCommand(['add', '.'], workingDirectory: workDir.path);
    await runGitCommand(
      ['commit', '-m', 'Add PR-only commit'],
      workingDirectory: workDir.path,
    );
    final shaResult = await runGitCommand(
      ['rev-parse', 'HEAD'],
      workingDirectory: workDir.path,
    );
    await runGitCommand(
      ['push', 'origin', 'HEAD:refs/pull/1/head'],
      workingDirectory: workDir.path,
    );

    return shaResult.stdout.toString().trim();
  } finally {
    if (workDir.existsSync()) {
      workDir.deleteSync(recursive: true);
    }
  }
}

class _FakeProcessService extends ProcessService {
  _FakeProcessService(super.context);

  ProcessException? exception;
  ProcessResult nextResult = ProcessResult(0, 0, '', '');
  String? lastCommand;
  List<String>? lastArgs;
  String? lastWorkingDirectory;
  Map<String, String>? lastEnvironment;
  bool? lastThrowOnError;
  bool? lastEchoOutput;
  bool? lastRunInShell;

  @override
  Future<ProcessResult> run(
    String command, {
    List<String> args = const [],
    String? workingDirectory,
    Map<String, String>? environment,
    bool throwOnError = true,
    bool echoOutput = false,
    bool runInShell = true,
  }) async {
    lastCommand = command;
    lastArgs = args;
    lastWorkingDirectory = workingDirectory;
    lastEnvironment = environment;
    lastThrowOnError = throwOnError;
    lastEchoOutput = echoOutput;
    lastRunInShell = runInShell;

    if (exception != null) {
      throw exception!;
    }

    return nextResult;
  }
}

void main() {
  group('FlutterService', () {
    group('install method', () {
      test('handles non-existent fork', () async {
        final context = TestFactory.context();
        final service = FlutterService(context);
        final version = FlutterVersion.parse('nonexistent-fork/stable');

        expect(
          () => service.install(version),
          throwsA(
            isA<AppException>().having(
              (e) => e.toString(),
              'message',
              contains('not found in configuration'),
            ),
          ),
        );
      });

      test(
        'preserves reference lookup errors from install flow',
        () async {
          final tempDir = createTempDir('fvm_flutter_service_reference_error');

          try {
            final remoteDir = await createLocalRemoteRepository(
              root: tempDir,
              name: 'flutter_origin',
            );

            final context = FvmContext.create(
              isTest: true,
              configOverrides: AppConfig(
                cachePath: p.join(tempDir.path, '.fvm'),
                flutterUrl: remoteDir.path,
                useGitCache: false,
              ),
            );

            final service = FlutterService(context);
            final version = FlutterVersion.parse('does-not-exist-1234');

            await expectLater(
              service.install(version),
              throwsA(
                isA<AppException>().having(
                  (e) => e.message,
                  'message',
                  allOf(
                    contains(
                      'Reference "${version.version}" was not found in the Flutter repository.',
                    ),
                    contains('Repository URL: ${remoteDir.path}'),
                  ),
                ),
              ),
            );
          } finally {
            if (tempDir.existsSync()) {
              tempDir.deleteSync(recursive: true);
            }
          }
        },
      );

      test(
        'preserves reference lookup errors after retrying from git cache to remote',
        () async {
          final tempDir = createTempDir(
            'fvm_flutter_service_reference_error_git_cache',
          );

          try {
            final remoteDir = await createLocalRemoteRepository(
              root: tempDir,
              name: 'flutter_origin',
            );

            final gitCachePath = p.join(tempDir.path, 'cache.git');
            Directory(gitCachePath).parent.createSync(recursive: true);
            await runGitCommand([
              'clone',
              '--mirror',
              remoteDir.path,
              gitCachePath,
            ]);

            final context = FvmContext.create(
              isTest: true,
              configOverrides: AppConfig(
                cachePath: p.join(tempDir.path, '.fvm'),
                gitCachePath: gitCachePath,
                flutterUrl: remoteDir.path,
                useGitCache: true,
              ),
            );

            final service = FlutterService(context);
            final version = FlutterVersion.parse('does-not-exist-1234');

            await expectLater(
              service.install(version),
              throwsA(
                isA<AppException>().having(
                  (e) => e.message,
                  'message',
                  allOf(
                    contains(
                      'Reference "${version.version}" was not found in the Flutter repository.',
                    ),
                    contains('Repository URL: ${remoteDir.path}'),
                  ),
                ),
              ),
            );
          } finally {
            if (tempDir.existsSync()) {
              tempDir.deleteSync(recursive: true);
            }
          }
        },
      );

      test('clones from local git cache and rewrites origin URL', () async {
        final tempDir = createTempDir('fvm_flutter_service_git_cache');

        try {
          final remoteDir = await createLocalRemoteRepository(
            root: tempDir,
            name: 'flutter_origin',
          );

          final cachePath = p.join(tempDir.path, '.fvm');
          final gitCachePath = p.join(tempDir.path, 'cache.git');
          Directory(gitCachePath).parent.createSync(recursive: true);
          await runGitCommand([
            'clone',
            '--mirror',
            remoteDir.path,
            gitCachePath,
          ]);

          final context = FvmContext.create(
            isTest: true,
            configOverrides: AppConfig(
              cachePath: cachePath,
              gitCachePath: gitCachePath,
              flutterUrl: remoteDir.path,
              useGitCache: true,
            ),
          );

          final service = FlutterService(context);
          final version = FlutterVersion.parse('master');

          await service.install(version);

          final cacheService = context.get<CacheService>();
          final versionDir = cacheService.getVersionCacheDir(version);

          final remoteResult = await runGitCommand([
            'remote',
            'get-url',
            'origin',
          ], workingDirectory: versionDir.path);

          expect(remoteResult.stdout.toString().trim(), remoteDir.path);

          final alternatesFile = File(
            p.join(versionDir.path, '.git', 'objects', 'info', 'alternates'),
          );
          expect(alternatesFile.existsSync(), isFalse);
        } finally {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        }
      });

      test(
        'removes stale git cache temp pack files before cache clone through GitService wrapper',
        () async {
          final tempDir = createTempDir('fvm_flutter_service_stale_pack');

          try {
            final remoteDir = await createLocalRemoteRepository(
              root: tempDir,
              name: 'flutter_origin',
            );

            final cachePath = p.join(tempDir.path, '.fvm');
            final gitCachePath = p.join(tempDir.path, 'cache.git');
            final context = FvmContext.create(
              isTest: true,
              configOverrides: AppConfig(
                cachePath: cachePath,
                gitCachePath: gitCachePath,
                flutterUrl: remoteDir.path,
                useGitCache: true,
              ),
            );

            await context.get<GitService>().updateLocalMirror();

            final packDir = Directory(p.join(gitCachePath, 'objects', 'pack'))
              ..createSync(recursive: true);
            final oldTimestamp = DateTime.now().subtract(
              const Duration(hours: 25),
            );
            final staleFiles = [
              File(p.join(packDir.path, 'tmp_pack_stale')),
              File(p.join(packDir.path, 'tmp_idx_stale')),
              File(p.join(packDir.path, 'tmp_rev_stale')),
            ];
            for (final file in staleFiles) {
              file.writeAsStringSync('stale');
              file.setLastModifiedSync(oldTimestamp);
            }

            final freshTemp = File(p.join(packDir.path, 'tmp_pack_fresh'))
              ..writeAsStringSync('fresh');
            final oldNonMatching = File(p.join(packDir.path, 'pack_tmp_old'))
              ..writeAsStringSync('old');
            oldNonMatching.setLastModifiedSync(oldTimestamp);

            final service = FlutterService(context);
            await service.install(FlutterVersion.parse('master'));

            for (final file in staleFiles) {
              expect(
                file.existsSync(),
                isFalse,
                reason: 'cleanup runs through install before cache clone',
              );
            }
            expect(freshTemp.existsSync(), isTrue);
            expect(oldNonMatching.existsSync(), isTrue);
          } finally {
            if (tempDir.existsSync()) {
              tempDir.deleteSync(recursive: true);
            }
          }
        },
      );

      test('clone from git cache waits for cache lock', () async {
        final tempDir = createTempDir('fvm_flutter_service_clone_lock');

        try {
          final remoteDir = await createLocalRemoteRepository(
            root: tempDir,
            name: 'flutter_origin',
          );

          final cachePath = p.join(tempDir.path, '.fvm');
          final gitCachePath = p.join(tempDir.path, 'cache.git');
          final context = FvmContext.create(
            isTest: true,
            configOverrides: AppConfig(
              cachePath: cachePath,
              gitCachePath: gitCachePath,
              flutterUrl: remoteDir.path,
              useGitCache: true,
            ),
          );

          await context.get<GitService>().updateLocalMirror();

          final lockHelper = File(
            p.join(tempDir.path, 'hold_git_cache_lock.dart'),
          )..writeAsStringSync('''
import 'dart:io';

Future<void> main(List<String> args) async {
  final lockFile = File(args[0]);
  lockFile.parent.createSync(recursive: true);
  final handle = await lockFile.open(mode: FileMode.write);
  await handle.lock(FileLock.exclusive);
  stdout.writeln('locked');
  await stdout.flush();
  await Future<void>.delayed(Duration(milliseconds: int.parse(args[1])));
  await handle.unlock();
  await handle.close();
}
''');

          final lockProcess = await Process.start(Platform.resolvedExecutable, [
            lockHelper.path,
            '$gitCachePath.lock',
            '1200',
          ]);

          final lockReady = lockProcess.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .firstWhere((line) => line.trim() == 'locked');

          await lockReady.timeout(const Duration(seconds: 5));

          final service = FlutterService(context);
          var completed = false;
          final operation =
              service.install(FlutterVersion.parse('master')).then((_) {
            completed = true;
          });

          await Future<void>.delayed(const Duration(milliseconds: 250));
          expect(completed, isFalse);

          final lockExitCode = await lockProcess.exitCode.timeout(
            const Duration(seconds: 5),
          );
          expect(lockExitCode, 0);

          await operation.timeout(const Duration(seconds: 5));
          expect(completed, isTrue);
        } finally {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        }
      });

      test(
        'falls back to remote clone when local git cache is unavailable',
        () async {
          final tempDir = createTempDir('fvm_flutter_service_fallback');

          try {
            final remoteDir = await createLocalRemoteRepository(
              root: tempDir,
              name: 'flutter_origin',
            );

            final cachePath = p.join(tempDir.path, '.fvm');
            final gitCachePath = p.join(tempDir.path, 'missing', 'cache.git');

            final context = FvmContext.create(
              isTest: true,
              configOverrides: AppConfig(
                cachePath: cachePath,
                gitCachePath: gitCachePath,
                flutterUrl: remoteDir.path,
                useGitCache: true,
              ),
            );

            final service = FlutterService(context);
            final version = FlutterVersion.parse('master');

            await service.install(version);

            final cacheService = context.get<CacheService>();
            final versionDir = cacheService.getVersionCacheDir(version);

            final remoteResult = await runGitCommand([
              'remote',
              'get-url',
              'origin',
            ], workingDirectory: versionDir.path);

            expect(remoteResult.stdout.toString().trim(), remoteDir.path);

            final logger = context.get<Logger>();
            expect(
              logger.outputs.any(
                (entry) => entry.contains('Falling back to remote clone'),
              ),
              isTrue,
            );
          } finally {
            if (tempDir.existsSync()) {
              tempDir.deleteSync(recursive: true);
            }
          }
        },
      );

      test(
        'retries with remote clone when git cache is missing reference',
        () async {
          final tempDir = createTempDir('fvm_flutter_service_retry');

          try {
            // Create remote and seed git cache before the new branch exists.
            final remoteDir = await createLocalRemoteRepository(
              root: tempDir,
              name: 'flutter_origin',
            );

            final gitCachePath = p.join(tempDir.path, 'cache.git');
            Directory(gitCachePath).parent.createSync(recursive: true);
            await runGitCommand([
              'clone',
              '--mirror',
              remoteDir.path,
              gitCachePath,
            ]);

            // Add a new branch to the remote after the git cache was created so
            // the cache does not contain the reference.
            final workDir = Directory(p.join(tempDir.path, 'work'))
              ..createSync();
            await runGitCommand(['clone', remoteDir.path, workDir.path]);
            await runGitCommand([
              'config',
              'user.email',
              'tests@fvm.app',
            ], workingDirectory: workDir.path);
            await runGitCommand([
              'config',
              'user.name',
              'FVM Tests',
            ], workingDirectory: workDir.path);
            await runGitCommand([
              'checkout',
              '-b',
              'feature',
            ], workingDirectory: workDir.path);
            File(
              p.join(workDir.path, 'FEATURE.md'),
            ).writeAsStringSync('feature');
            await runGitCommand(['add', '.'], workingDirectory: workDir.path);
            await runGitCommand([
              'commit',
              '-m',
              'Add feature branch',
            ], workingDirectory: workDir.path);
            await runGitCommand([
              'push',
              'origin',
              'feature',
            ], workingDirectory: workDir.path);

            final cachePath = p.join(tempDir.path, '.fvm');

            final context = FvmContext.create(
              isTest: true,
              configOverrides: AppConfig(
                cachePath: cachePath,
                gitCachePath: gitCachePath,
                flutterUrl: remoteDir.path,
                useGitCache: true,
              ),
            );

            final service = FlutterService(context);
            final version = FlutterVersion.parse('feature');

            await service.install(version);

            final cacheService = context.get<CacheService>();
            final versionDir = cacheService.getVersionCacheDir(version);

            final headResult = await runGitCommand([
              'rev-parse',
              '--abbrev-ref',
              'HEAD',
            ], workingDirectory: versionDir.path);

            expect(headResult.stdout.toString().trim(), 'feature');
          } finally {
            if (tempDir.existsSync()) {
              tempDir.deleteSync(recursive: true);
            }
          }
        },
      );

      test('installs reachable commit hash from heads/tags git cache',
          () async {
        final tempDir = createTempDir('fvm_flutter_service_cached_commit');

        try {
          final remoteDir = await createLocalRemoteRepository(
            root: tempDir,
            name: 'flutter_origin',
          );
          final shaResult = await runGitCommand(
            ['rev-parse', 'master'],
            workingDirectory: remoteDir.path,
          );
          final commitSha = shaResult.stdout.toString().trim();

          final cachePath = p.join(tempDir.path, '.fvm');
          final gitCachePath = p.join(tempDir.path, 'cache.git');
          final context = FvmContext.create(
            isTest: true,
            configOverrides: AppConfig(
              cachePath: cachePath,
              gitCachePath: gitCachePath,
              flutterUrl: remoteDir.path,
              useGitCache: true,
            ),
          );
          await context.get<GitService>().updateLocalMirror();

          final hiddenRemoteDir = Directory(p.join(tempDir.path, 'hidden.git'));
          remoteDir.renameSync(hiddenRemoteDir.path);

          final version = FlutterVersion.parse(commitSha);
          final service = FlutterService(context);
          await service.install(version);

          final versionDir = context.get<CacheService>().getVersionCacheDir(
                version,
              );
          final installedShaResult = await runGitCommand(
            ['rev-parse', 'HEAD'],
            workingDirectory: versionDir.path,
          );
          expect(installedShaResult.stdout.toString().trim(), commitSha);
        } finally {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        }
      });

      test('retries remote clone when commit hash is missing from git cache',
          () async {
        final tempDir = createTempDir('fvm_flutter_service_missing_commit');

        try {
          final remoteDir = await createLocalRemoteRepository(
            root: tempDir,
            name: 'flutter_origin',
          );

          final cachePath = p.join(tempDir.path, '.fvm');
          final gitCachePath = p.join(tempDir.path, 'cache.git');
          final context = FvmContext.create(
            isTest: true,
            configOverrides: AppConfig(
              cachePath: cachePath,
              gitCachePath: gitCachePath,
              flutterUrl: remoteDir.path,
              useGitCache: true,
            ),
          );
          await context.get<GitService>().updateLocalMirror();

          final newCommitSha = await _commitToRemoteBranch(
            root: tempDir,
            remoteDir: remoteDir,
            fileName: 'NEW_COMMIT.md',
          );

          final version = FlutterVersion.parse(newCommitSha);
          final service = FlutterService(context);
          await service.install(version);

          final versionDir = context.get<CacheService>().getVersionCacheDir(
                version,
              );
          final installedShaResult = await runGitCommand(
            ['rev-parse', 'HEAD'],
            workingDirectory: versionDir.path,
          );
          expect(installedShaResult.stdout.toString().trim(), newCommitSha);
        } finally {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        }
      });

      test('install can bypass a stale local git cache', () async {
        final tempDir = createTempDir('fvm_flutter_service_bypass_cache');

        try {
          final remoteDir = await createLocalRemoteRepository(
            root: tempDir,
            name: 'flutter_origin',
          );
          final oldShaResult = await runGitCommand(
            ['rev-parse', 'master'],
            workingDirectory: remoteDir.path,
          );
          final oldSha = oldShaResult.stdout.toString().trim();

          final gitCachePath = p.join(tempDir.path, 'cache.git');
          Directory(gitCachePath).parent.createSync(recursive: true);
          await runGitCommand(['clone', remoteDir.path, gitCachePath]);

          final newSha = await _commitToRemoteBranch(
            root: tempDir,
            remoteDir: remoteDir,
            fileName: 'REMOTE_ONLY.md',
          );

          final context = FvmContext.create(
            isTest: true,
            configOverrides: AppConfig(
              cachePath: p.join(tempDir.path, '.fvm'),
              gitCachePath: gitCachePath,
              flutterUrl: Uri.file(remoteDir.path).toString(),
              useGitCache: true,
            ),
          );

          final service = FlutterService(context);
          final version = FlutterVersion.parse('master');
          await service.install(version, useGitCache: false);

          final versionDir = context.get<CacheService>().getVersionCacheDir(
                version,
              );
          final installedShaResult = await runGitCommand(
            ['rev-parse', 'HEAD'],
            workingDirectory: versionDir.path,
          );
          final installedSha = installedShaResult.stdout.toString().trim();

          expect(installedSha, newSha);
          expect(installedSha, isNot(oldSha));
        } finally {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        }
      });

      test(
          'ensure workflow does not install channel from stale preserved cache',
          () async {
        final tempDir = createTempDir(
          'fvm_flutter_service_stale_preserved_cache',
        );

        try {
          final remoteDir = await createLocalRemoteRepository(
            root: tempDir,
            name: 'flutter_origin',
          );
          final oldShaResult = await runGitCommand(
            ['rev-parse', 'master'],
            workingDirectory: remoteDir.path,
          );
          final oldSha = oldShaResult.stdout.toString().trim();

          final cachePath = p.join(tempDir.path, '.fvm');
          final gitCachePath = p.join(tempDir.path, 'cache.git');
          Directory(gitCachePath).parent.createSync(recursive: true);
          await runGitCommand(['clone', remoteDir.path, gitCachePath]);

          final newSha = await _commitToRemoteBranch(
            root: tempDir,
            remoteDir: remoteDir,
            fileName: 'REMOTE_UPDATE.md',
          );

          final context = FvmContext.create(
            isTest: true,
            configOverrides: AppConfig(
              cachePath: cachePath,
              gitCachePath: gitCachePath,
              flutterUrl: Uri.file(remoteDir.path).toString(),
              useGitCache: true,
            ),
          );

          final brokenVersionDir = Directory(
            p.join(context.versionsCachePath, 'broken'),
          );
          File(p.join(brokenVersionDir.path, 'version'))
            ..createSync(recursive: true)
            ..writeAsStringSync('broken');
          final alternatesFile = File(
            p.join(
              brokenVersionDir.path,
              '.git',
              'objects',
              'info',
              'alternates',
            ),
          )..createSync(recursive: true);
          alternatesFile.writeAsStringSync(
            '${p.join(gitCachePath, '.git', 'objects')}\n',
          );

          final version = FlutterVersion.parse('master');
          await EnsureCacheWorkflow(context).call(version, shouldInstall: true);

          final versionDir = context.get<CacheService>().getVersionCacheDir(
                version,
              );
          final installedShaResult = await runGitCommand(
            ['rev-parse', 'HEAD'],
            workingDirectory: versionDir.path,
          );
          final installedSha = installedShaResult.stdout.toString().trim();

          expect(installedSha, newSha);
          expect(installedSha, isNot(oldSha));
          expect(brokenVersionDir.existsSync(), isFalse);
          expect(await isBareGitRepository(gitCachePath), isTrue);
        } finally {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        }
      });

      test('does not cache PR-only hidden refs by default', () async {
        final tempDir = createTempDir('fvm_flutter_service_pr_only');

        try {
          final remoteDir = await createLocalRemoteRepository(
            root: tempDir,
            name: 'flutter_origin',
          );
          final prOnlySha = await _pushPrOnlyCommit(
            root: tempDir,
            remoteDir: remoteDir,
          );

          final cachePath = p.join(tempDir.path, '.fvm');
          final gitCachePath = p.join(tempDir.path, 'cache.git');
          final context = FvmContext.create(
            isTest: true,
            configOverrides: AppConfig(
              cachePath: cachePath,
              gitCachePath: gitCachePath,
              flutterUrl: Uri.file(remoteDir.path).toString(),
              useGitCache: true,
            ),
          );
          await context.get<GitService>().updateLocalMirror();

          final refsResult = await runGitCommand(
            ['for-each-ref', '--format=%(refname)'],
            workingDirectory: gitCachePath,
          );
          expect(
            refsResult.stdout.toString(),
            isNot(contains('refs/pull/1/head')),
          );

          final catFileResult = await Process.run(
            'git',
            ['cat-file', '-e', '$prOnlySha^{commit}'],
            workingDirectory: gitCachePath,
            runInShell: true,
          );
          expect(catFileResult.exitCode, isNot(0));

          final service = FlutterService(context);
          await expectLater(
            service.install(FlutterVersion.parse(prOnlySha)),
            throwsA(
              isA<AppException>().having(
                (e) => e.message,
                'message',
                contains('was not found in the Flutter repository'),
              ),
            ),
          );
        } finally {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        }
      });

      test('falls back to remote when git cache has missing objects', () async {
        final tempDir = createTempDir('fvm_flutter_service_missing_objects');

        try {
          final remoteDir = await createLocalRemoteRepository(
            root: tempDir,
            name: 'flutter_origin',
          );

          // Create a feature branch in the remote.
          final workDir = Directory(p.join(tempDir.path, 'work'))..createSync();
          await runGitCommand(['clone', remoteDir.path, workDir.path]);
          await runGitCommand([
            'config',
            'user.email',
            'tests@fvm.app',
          ], workingDirectory: workDir.path);
          await runGitCommand([
            'config',
            'user.name',
            'FVM Tests',
          ], workingDirectory: workDir.path);
          await runGitCommand([
            'checkout',
            '-b',
            'feature',
          ], workingDirectory: workDir.path);
          File(p.join(workDir.path, 'FEATURE.md')).writeAsStringSync('feature');
          await runGitCommand(['add', '.'], workingDirectory: workDir.path);
          await runGitCommand([
            'commit',
            '-m',
            'Add feature branch',
          ], workingDirectory: workDir.path);
          await runGitCommand([
            'push',
            'origin',
            'feature',
          ], workingDirectory: workDir.path);

          final gitCachePath = p.join(tempDir.path, 'cache.git');
          Directory(gitCachePath).parent.createSync(recursive: true);
          await runGitCommand([
            'clone',
            '--mirror',
            remoteDir.path,
            gitCachePath,
          ]);

          final featureShaResult = await runGitCommand([
            'rev-parse',
            'feature',
          ], workingDirectory: gitCachePath);
          final featureSha = featureShaResult.stdout.toString().trim();
          await _deleteLooseGitObject(
            repoPath: gitCachePath,
            objectSha: featureSha,
          );

          final cachePath = p.join(tempDir.path, '.fvm');
          final context = FvmContext.create(
            isTest: true,
            configOverrides: AppConfig(
              cachePath: cachePath,
              gitCachePath: gitCachePath,
              flutterUrl: remoteDir.path,
              useGitCache: true,
            ),
          );

          final service = FlutterService(context);
          final version = FlutterVersion.parse('feature');

          await service.install(version);

          final cacheService = context.get<CacheService>();
          final versionDir = cacheService.getVersionCacheDir(version);
          final headResult = await runGitCommand([
            'rev-parse',
            '--abbrev-ref',
            'HEAD',
          ], workingDirectory: versionDir.path);

          expect(headResult.stdout.toString().trim(), 'feature');
        } finally {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        }
      });

      test(
          'rethrows dependent SDK removal failure during corrupted cache cleanup',
          () async {
        final tempDir = createTempDir('fvm_flutter_service_cleanup_blocked');

        try {
          final gitCachePath = p.join(tempDir.path, 'cache.git');
          Directory(gitCachePath).createSync(recursive: true);
          final context = FvmContext.create(
            isTest: true,
            configOverrides: AppConfig(
              cachePath: p.join(tempDir.path, '.fvm'),
              gitCachePath: gitCachePath,
              flutterUrl: 'https://example.com/flutter.git',
              useGitCache: true,
            ),
            generatorsOverride: {
              GitService: (ctx) => _GitCacheCleanupBlockedGitService(ctx),
            },
          );

          final service = FlutterService(context);
          await expectLater(
            service.install(FlutterVersion.parse('master')),
            throwsA(isA<GitCacheDependentSdkRemovalException>()),
          );
        } finally {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        }
      });
    });

    group('setup method', () {
      test('calls flutter --version command', () async {
        late _FakeProcessService processService;
        final context = TestFactory.context(
          generators: {
            ProcessService: (ctx) {
              processService = _FakeProcessService(ctx);
              return processService;
            },
          },
        );
        final service = FlutterService(context);

        final flutterVersion = FlutterVersion.parse('stable');
        final mockCacheVersion = CacheFlutterVersion.fromVersion(
          flutterVersion,
          directory: p.join(context.versionsCachePath, 'stable'),
        );

        final result = await service.setup(mockCacheVersion);

        expect(result.exitCode, equals(0));
        expect(
          processService.lastCommand,
          equals(p.absolute(mockCacheVersion.flutterExec)),
        );
        expect(processService.lastArgs, equals(['--version']));
        expect(processService.lastWorkingDirectory, isNull);
        expect(processService.lastThrowOnError, isFalse);
        expect(processService.lastEchoOutput, isTrue);
        expect(processService.lastRunInShell, isFalse);
        final pathValue = processService.lastEnvironment?['PATH'];
        expect(pathValue, isNotNull);
        expect(pathValue, contains(mockCacheVersion.binPath));
        expect(pathValue, contains(mockCacheVersion.dartBinPath));
      });
    });

    group('runFlutter method', () {
      test('executes flutter command with the specified args', () async {
        late _FakeProcessService processService;
        final context = TestFactory.context(
          generators: {
            ProcessService: (ctx) {
              processService = _FakeProcessService(ctx);
              return processService;
            },
          },
        );
        final service = FlutterService(context);

        final flutterVersion = FlutterVersion.parse('stable');
        final mockCacheVersion = CacheFlutterVersion.fromVersion(
          flutterVersion,
          directory: p.join(context.versionsCachePath, 'stable'),
        );

        final result = await service.runFlutter(['--help'], mockCacheVersion);

        expect(result.exitCode, equals(0));
        expect(
          processService.lastCommand,
          equals(p.absolute(mockCacheVersion.flutterExec)),
        );
        expect(processService.lastArgs, equals(['--help']));
        expect(processService.lastWorkingDirectory, isNull);
        expect(processService.lastThrowOnError, isFalse);
        expect(processService.lastEchoOutput, isTrue);
        expect(processService.lastRunInShell, isFalse);
        final pathValue = processService.lastEnvironment?['PATH'];
        expect(pathValue, isNotNull);
        expect(pathValue, contains(mockCacheVersion.binPath));
        expect(pathValue, contains(mockCacheVersion.dartBinPath));
      });
    });

    group('pubGet method', () {
      test('executes flutter pub get command', () async {
        late _FakeProcessService processService;
        final context = TestFactory.context(
          generators: {
            ProcessService: (ctx) {
              processService = _FakeProcessService(ctx);
              return processService;
            },
          },
        );
        final service = FlutterService(context);

        final flutterVersion = FlutterVersion.parse('stable');
        final mockCacheVersion = CacheFlutterVersion.fromVersion(
          flutterVersion,
          directory: p.join(context.versionsCachePath, 'stable'),
        );

        final result = await service.pubGet(mockCacheVersion);

        expect(result.exitCode, equals(0));
        expect(
          processService.lastCommand,
          equals(p.absolute(mockCacheVersion.flutterExec)),
        );
        expect(processService.lastArgs, equals(['pub', 'get']));
        expect(processService.lastWorkingDirectory, isNull);
        expect(processService.lastThrowOnError, isFalse);
        expect(processService.lastEchoOutput, isTrue);
        expect(processService.lastRunInShell, isFalse);
        final pathValue = processService.lastEnvironment?['PATH'];
        expect(pathValue, isNotNull);
        expect(pathValue, contains(mockCacheVersion.binPath));
        expect(pathValue, contains(mockCacheVersion.dartBinPath));
      });

      test('adds --offline flag in offline mode', () async {
        late _FakeProcessService processService;
        final context = TestFactory.context(
          generators: {
            ProcessService: (ctx) {
              processService = _FakeProcessService(ctx);
              return processService;
            },
          },
        );
        final service = FlutterService(context);

        final flutterVersion = FlutterVersion.parse('stable');
        final mockCacheVersion = CacheFlutterVersion.fromVersion(
          flutterVersion,
          directory: p.join(context.versionsCachePath, 'stable'),
        );

        final result = await service.pubGet(mockCacheVersion, offline: true);

        expect(result.exitCode, equals(0));
        expect(
          processService.lastCommand,
          equals(p.absolute(mockCacheVersion.flutterExec)),
        );
        expect(processService.lastArgs, equals(['pub', 'get', '--offline']));
        expect(processService.lastWorkingDirectory, isNull);
        expect(processService.lastThrowOnError, isFalse);
        expect(processService.lastEchoOutput, isFalse);
        expect(processService.lastRunInShell, isFalse);
        final pathValue = processService.lastEnvironment?['PATH'];
        expect(pathValue, isNotNull);
        expect(pathValue, contains(mockCacheVersion.binPath));
        expect(pathValue, contains(mockCacheVersion.dartBinPath));
      });
    });

    group('VersionRunner', () {
      test('ignores project collisions for Flutter and Dart commands', () async {
        final projectDirectory = createTempDir('sdk_command_collision');
        final collisions = {
          'flutter': File(
            p.join(projectDirectory.path, flutterExecFileName),
          )..writeAsStringSync('project flutter collision'),
          'dart': File(
            p.join(projectDirectory.path, dartExecFileName),
          )..writeAsStringSync('project dart collision'),
        };
        late _FakeProcessService processService;
        final context = TestFactory.context(
          workingDirectoryOverride: projectDirectory.path,
          generators: {
            ProcessService: (ctx) {
              processService = _FakeProcessService(ctx);
              return processService;
            },
          },
        );

        final flutterVersion = FlutterVersion.parse('stable');
        final mockCacheVersion = CacheFlutterVersion.fromVersion(
          flutterVersion,
          directory: p.join(context.versionsCachePath, 'stable'),
        );

        final versionRunner = VersionRunner(
          context: context,
          version: mockCacheVersion,
        );

        final expectedExecutables = {
          'flutter': mockCacheVersion.flutterExec,
          'dart': mockCacheVersion.dartExec,
        };

        for (final command in expectedExecutables.keys) {
          await versionRunner.run(command, ['--version']);

          expect(
            processService.lastCommand,
            equals(p.absolute(expectedExecutables[command]!)),
          );
          expect(
            processService.lastCommand,
            isNot(equals(collisions[command]!.absolute.path)),
          );
          expect(processService.lastArgs, equals(['--version']));
          expect(processService.lastRunInShell, isFalse);
        }
      });

      test('preserves shell lookup for custom exec commands', () async {
        late _FakeProcessService processService;
        final context = TestFactory.context(
          generators: {
            ProcessService: (ctx) {
              processService = _FakeProcessService(ctx);
              return processService;
            },
          },
        );
        final mockCacheVersion = CacheFlutterVersion.fromVersion(
          FlutterVersion.parse('stable'),
          directory: p.join(context.versionsCachePath, 'stable'),
        );
        final versionRunner = VersionRunner(
          context: context,
          version: mockCacheVersion,
        );

        await versionRunner.run('melos', ['bootstrap']);

        expect(processService.lastCommand, equals('melos'));
        expect(processService.lastArgs, equals(['bootstrap']));
        expect(processService.lastRunInShell, isTrue);
        expect(
          processService.lastEnvironment?['PATH'],
          contains(mockCacheVersion.binPath),
        );
      });
    });
  });
}

class _GitCacheCleanupBlockedGitService extends GitService {
  _GitCacheCleanupBlockedGitService(super.context);

  @override
  Future<T> withPreparedGitCacheForClone<T>(
    Future<T> Function() action,
  ) async {
    throw ProcessException('git', const ['clone'], 'bad object', 128);
  }

  @override
  Future<bool> removeLocalMirror({
    bool requireSuccess = false,
    void Function(FileSystemException error)? onFinalError,
  }) async {
    throw const GitCacheDependentSdkRemovalException('blocked by test');
  }
}
