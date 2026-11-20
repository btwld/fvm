@Tags(['git'])
import 'dart:convert';
import 'dart:io';

import 'package:fvm/fvm.dart';
import 'package:fvm/src/services/git_service.dart';
import 'package:fvm/src/services/process_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../testing_utils.dart';

class _FakeProcessService extends ProcessService {
  _FakeProcessService(super.context);

  ProcessException? exception;
  String? lastCommand;
  List<String>? lastArgs;
  String? lastWorkingDirectory;

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

    if (exception != null) {
      throw exception!;
    }

    return ProcessResult(0, 0, '', '');
  }
}

class _CountingProcessService extends ProcessService {
  _CountingProcessService(super.context);

  int connectivityFsckCount = 0;

  void reset() {
    connectivityFsckCount = 0;
  }

  @override
  Future<ProcessResult> run(
    String command, {
    List<String> args = const [],
    String? workingDirectory,
    Map<String, String>? environment,
    bool throwOnError = true,
    bool echoOutput = false,
    bool runInShell = true,
  }) {
    if (command == 'git' &&
        args.length == 2 &&
        args[0] == 'fsck' &&
        args[1] == '--connectivity-only') {
      connectivityFsckCount++;
    }

    return super.run(
      command,
      args: args,
      workingDirectory: workingDirectory,
      environment: environment,
      throwOnError: throwOnError,
      echoOutput: echoOutput,
      runInShell: runInShell,
    );
  }
}

Future<List<String>> _gitConfigValues(String repoPath, String key) async {
  final result = await runGitCommand(
    ['config', '--get-all', key],
    workingDirectory: repoPath,
  );

  return result.stdout
      .toString()
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

Future<List<String>> _gitRefs(String repoPath) async {
  final result = await runGitCommand(
    ['for-each-ref', '--format=%(refname)'],
    workingDirectory: repoPath,
  );

  return result.stdout
      .toString()
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

Future<void> _addHiddenAndTagRefs(Directory remoteDir) async {
  final headResult = await runGitCommand(
    ['rev-parse', 'master'],
    workingDirectory: remoteDir.path,
  );
  final headSha = headResult.stdout.toString().trim();

  await runGitCommand(
    ['update-ref', 'refs/tags/test-tag', headSha],
    workingDirectory: remoteDir.path,
  );
  await runGitCommand(
    ['update-ref', 'refs/pull/1/head', headSha],
    workingDirectory: remoteDir.path,
  );
}

Future<String> _pushBranchToRemote({
  required Directory root,
  required Directory remoteDir,
  required String branchName,
}) async {
  final workDir = Directory(p.join(root.path, '${branchName}_work'))
    ..createSync(recursive: true);

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
    ['checkout', '-b', branchName],
    workingDirectory: workDir.path,
  );
  File(p.join(workDir.path, '$branchName.md')).writeAsStringSync(branchName);
  await runGitCommand(['add', '.'], workingDirectory: workDir.path);
  await runGitCommand(
    ['commit', '-m', 'Add $branchName branch'],
    workingDirectory: workDir.path,
  );
  await runGitCommand(
    ['push', 'origin', branchName],
    workingDirectory: workDir.path,
  );

  final revParse = await runGitCommand(
    ['rev-parse', 'HEAD'],
    workingDirectory: workDir.path,
  );

  return revParse.stdout.toString().trim();
}

/// Creates a repository with committed history, a staged change, and an
/// untracked file -- state that a stray `reset --hard` / `clean -fdx` from a
/// misdirected cache migration would destroy.
Future<Directory> _createVictimRepository(Directory root, String name) async {
  final victimDir = Directory(p.join(root.path, name))
    ..createSync(recursive: true);
  await runGitCommand(['init'], workingDirectory: victimDir.path);
  await runGitCommand(
    ['config', 'user.email', 'tests@fvm.app'],
    workingDirectory: victimDir.path,
  );
  await runGitCommand(
    ['config', 'user.name', 'FVM Tests'],
    workingDirectory: victimDir.path,
  );
  File(p.join(victimDir.path, 'tracked.txt')).writeAsStringSync('original');
  await runGitCommand(['add', '.'], workingDirectory: victimDir.path);
  await runGitCommand(
    ['commit', '-m', 'seed'],
    workingDirectory: victimDir.path,
  );
  File(p.join(victimDir.path, 'tracked.txt')).writeAsStringSync('staged');
  await runGitCommand(
    ['add', 'tracked.txt'],
    workingDirectory: victimDir.path,
  );
  File(p.join(victimDir.path, 'untracked.txt')).writeAsStringSync('untracked');

  return victimDir;
}

Future<void> _expectVictimRepositoryIntact(Directory victimDir) async {
  final staged = await runGitCommand(
    ['diff', '--cached', '--name-only'],
    workingDirectory: victimDir.path,
  );
  expect(
    staged.stdout.toString().trim(),
    'tracked.txt',
    reason: 'staged change must survive',
  );
  expect(
    File(p.join(victimDir.path, 'tracked.txt')).readAsStringSync(),
    'staged',
    reason: 'working tree must survive',
  );
  expect(
    File(p.join(victimDir.path, 'untracked.txt')).existsSync(),
    isTrue,
    reason: 'untracked file must survive',
  );
}

Future<void> _expectHeadsTagsOnlyCache(String gitCachePath) async {
  expect(await isBareGitRepository(gitCachePath), isTrue);

  final refspecs = await _gitConfigValues(
    gitCachePath,
    'remote.origin.fetch',
  );
  expect(
    refspecs,
    unorderedEquals([
      '+refs/heads/*:refs/heads/*',
      '+refs/tags/*:refs/tags/*',
    ]),
  );

  final tagOpt = await _gitConfigValues(gitCachePath, 'remote.origin.tagOpt');
  expect(tagOpt, equals(['--no-tags']));

  final mirrorConfig = await Process.run(
    'git',
    ['config', '--get-all', 'remote.origin.mirror'],
    workingDirectory: gitCachePath,
    runInShell: true,
  );
  expect(mirrorConfig.exitCode, isNot(0));

  final refs = await _gitRefs(gitCachePath);
  expect(
    refs.every(
      (ref) => ref.startsWith('refs/heads/') || ref.startsWith('refs/tags/'),
    ),
    isTrue,
  );

  final head = await runGitCommand(
    ['symbolic-ref', '--quiet', 'HEAD'],
    workingDirectory: gitCachePath,
  );
  final headRef = head.stdout.toString().trim();
  expect(headRef, startsWith('refs/heads/'));
  expect(refs, contains(headRef));
}

void main() {
  group('GitService', () {
    late FvmContext context;
    late GitService gitService;
    late _FakeProcessService processService;

    setUp(() {
      context = TestFactory.context(
        generators: {
          ProcessService: (ctx) {
            processService = _FakeProcessService(ctx);
            return processService;
          },
        },
      );

      gitService = GitService(context);
    });

    test('throws AppException when git command fails', () async {
      context.get<ProcessService>();
      processService.exception = ProcessException(
        'git',
        ['ls-remote', '--tags', '--branches', context.flutterUrl],
        'fatal: git not found',
        127,
      );

      await expectLater(
        gitService.isGitReference('stable'),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Failed to fetch git references from'),
              contains('Ensure git is installed'),
            ),
          ),
        ),
      );
    });

    test('AppException message includes flutter URL', () async {
      context.get<ProcessService>();
      processService.exception = ProcessException(
        'git',
        const ['ls-remote'],
        'fatal: unable to access',
        128,
      );

      await expectLater(
        gitService.isGitReference('beta'),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains(context.flutterUrl),
          ),
        ),
      );
    });

    test('setOriginUrl delegates to ProcessService', () async {
      context.get<ProcessService>();
      const repoPath = '/tmp/fvm-test-repo';
      const url = 'https://example.com/flutter.git';

      await gitService.setOriginUrl(repositoryPath: repoPath, url: url);

      expect(processService.lastCommand, equals('git'));
      expect(
        processService.lastArgs,
        equals(['remote', 'set-url', 'origin', url]),
      );
      expect(processService.lastWorkingDirectory, equals(repoPath));
    });
  });

  group('GitService cache state detection', () {
    late Directory tempDir;
    late Directory remoteDir;

    setUp(() async {
      tempDir = createTempDir('fvm_cache_state_test');
      remoteDir = await createLocalRemoteRepository(
        root: tempDir,
        name: 'flutter_remote',
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('creates heads/tags git cache when cache directory is missing',
        () async {
      await _addHiddenAndTagRefs(remoteDir);

      final gitCachePath = p.join(tempDir.path, 'cache.git');
      final context = FvmContext.create(
        isTest: true,
        configOverrides: AppConfig(
          cachePath: p.join(tempDir.path, '.fvm'),
          gitCachePath: gitCachePath,
          flutterUrl: remoteDir.path,
          useGitCache: true,
        ),
      );

      expect(Directory(gitCachePath).existsSync(), isFalse);

      final gitService = GitService(context);
      await gitService.updateLocalMirror();

      expect(Directory(gitCachePath).existsSync(), isTrue);
      await _expectHeadsTagsOnlyCache(gitCachePath);

      final refs = await _gitRefs(gitCachePath);
      expect(refs, contains('refs/tags/test-tag'));
      expect(refs, isNot(contains('refs/pull/1/head')));
    });

    test(
      'preserves overbroad mirror cache when rebuild fails against missing remote',
      () async {
        await _addHiddenAndTagRefs(remoteDir);
        final gitCachePath = p.join(tempDir.path, 'cache.git');

        await runGitCommand(
            ['clone', '--mirror', remoteDir.path, gitCachePath]);
        expect(await isBareGitRepository(gitCachePath), isTrue);

        final refsBefore = await _gitRefs(gitCachePath);
        expect(refsBefore, contains('refs/pull/1/head'));
        expect(refsBefore, contains('refs/tags/test-tag'));

        final missingRemote = p.join(tempDir.path, 'missing_remote');
        final context = FvmContext.create(
          isTest: true,
          configOverrides: AppConfig(
            cachePath: p.join(tempDir.path, '.fvm'),
            gitCachePath: gitCachePath,
            flutterUrl: missingRemote,
            useGitCache: true,
          ),
        );

        final gitService = GitService(context);
        await expectLater(
          gitService.updateLocalMirror(),
          throwsA(isA<AppException>()),
        );

        expect(Directory(gitCachePath).existsSync(), isTrue);
        final refsAfter = await _gitRefs(gitCachePath);
        expect(refsAfter, contains('refs/pull/1/head'));
        expect(refsAfter, contains('refs/tags/test-tag'));
      },
    );

    test('replaces overbroad bare mirror with heads/tags git cache', () async {
      await _addHiddenAndTagRefs(remoteDir);
      final gitCachePath = p.join(tempDir.path, 'cache.git');

      await runGitCommand(['clone', '--mirror', remoteDir.path, gitCachePath]);
      expect(await isBareGitRepository(gitCachePath), isTrue);
      expect(await _gitRefs(gitCachePath), contains('refs/pull/1/head'));

      final context = FvmContext.create(
        isTest: true,
        configOverrides: AppConfig(
          cachePath: p.join(tempDir.path, '.fvm'),
          gitCachePath: gitCachePath,
          flutterUrl: remoteDir.path,
          useGitCache: true,
        ),
      );

      final gitService = GitService(context);
      await gitService.updateLocalMirror();

      await _expectHeadsTagsOnlyCache(gitCachePath);

      final refs = await _gitRefs(gitCachePath);
      expect(refs, contains('refs/tags/test-tag'));
      expect(refs, isNot(contains('refs/pull/1/head')));
    });

    test('treats leftover mirror config as not ready during migration',
        () async {
      final gitCachePath = p.join(tempDir.path, 'cache.git');
      final context = FvmContext.create(
        isTest: true,
        configOverrides: AppConfig(
          cachePath: p.join(tempDir.path, '.fvm'),
          gitCachePath: gitCachePath,
          flutterUrl: remoteDir.path,
          useGitCache: true,
        ),
      );

      final gitService = GitService(context);
      await gitService.updateLocalMirror();
      await runGitCommand(
        ['config', 'remote.origin.mirror', 'true'],
        workingDirectory: gitCachePath,
      );

      await gitService.ensureBareCacheIfPresent();

      await _expectHeadsTagsOnlyCache(gitCachePath);
    });

    test('preserves legacy remote-tracking branches during local migration',
        () async {
      final stableSha = await _pushBranchToRemote(
        root: tempDir,
        remoteDir: remoteDir,
        branchName: 'stable',
      );
      final gitCachePath = p.join(tempDir.path, 'cache.git');
      await runGitCommand(['clone', remoteDir.path, gitCachePath]);

      final remoteRefsBefore = await _gitRefs(gitCachePath);
      expect(remoteRefsBefore, contains('refs/remotes/origin/stable'));
      expect(remoteRefsBefore, isNot(contains('refs/heads/stable')));

      final context = FvmContext.create(
        isTest: true,
        configOverrides: AppConfig(
          cachePath: p.join(tempDir.path, '.fvm'),
          gitCachePath: gitCachePath,
          flutterUrl: remoteDir.path,
          useGitCache: true,
        ),
      );

      final gitService = GitService(context);
      await gitService.ensureBareCacheIfPresent();

      await _expectHeadsTagsOnlyCache(gitCachePath);
      final refs = await _gitRefs(gitCachePath);
      expect(refs, contains('refs/heads/stable'));

      final stableResult = await runGitCommand(
        ['rev-parse', 'refs/heads/stable'],
        workingDirectory: gitCachePath,
      );
      expect(stableResult.stdout.toString().trim(), stableSha);
    });

    test('recreates git cache when cache directory is invalid', () async {
      final gitCachePath = p.join(tempDir.path, 'cache.git');

      Directory(gitCachePath).createSync(recursive: true);
      expect(Directory(gitCachePath).existsSync(), isTrue);

      final context = FvmContext.create(
        isTest: true,
        configOverrides: AppConfig(
          cachePath: p.join(tempDir.path, '.fvm'),
          gitCachePath: gitCachePath,
          flutterUrl: remoteDir.path,
          useGitCache: true,
        ),
      );

      final gitService = GitService(context);
      await gitService.updateLocalMirror();

      await _expectHeadsTagsOnlyCache(gitCachePath);
    });

    test('sets bare HEAD to main when remote HEAD still points at master',
        () async {
      final mainRemoteDir = await createLocalRemoteRepository(
        root: tempDir,
        name: 'flutter_main_remote',
        branch: 'main',
      );
      final gitCachePath = p.join(tempDir.path, 'main_cache.git');
      final context = FvmContext.create(
        isTest: true,
        configOverrides: AppConfig(
          cachePath: p.join(tempDir.path, '.fvm_main'),
          gitCachePath: gitCachePath,
          flutterUrl: mainRemoteDir.path,
          useGitCache: true,
        ),
      );

      final gitService = GitService(context);
      await gitService.updateLocalMirror();

      await _expectHeadsTagsOnlyCache(gitCachePath);
      final head = await runGitCommand(
        ['symbolic-ref', '--quiet', 'HEAD'],
        workingDirectory: gitCachePath,
      );
      expect(head.stdout.toString().trim(), 'refs/heads/main');
    });

    test(
      'updateLocalMirror validates ready cache only after sync',
      () async {
        final gitCachePath = p.join(tempDir.path, 'counted_cache.git');
        late _CountingProcessService processService;
        final context = FvmContext.create(
          isTest: true,
          configOverrides: AppConfig(
            cachePath: p.join(tempDir.path, '.fvm_counted'),
            gitCachePath: gitCachePath,
            flutterUrl: remoteDir.path,
            useGitCache: true,
          ),
          generatorsOverride: {
            ProcessService: (ctx) {
              processService = _CountingProcessService(ctx);

              return processService;
            },
          },
        );

        final gitService = GitService(context);
        await gitService.updateLocalMirror();
        await _expectHeadsTagsOnlyCache(gitCachePath);

        processService.reset();
        await gitService.updateLocalMirror();

        expect(processService.connectivityFsckCount, 1);
        await _expectHeadsTagsOnlyCache(gitCachePath);

        processService.reset();
        await gitService.ensureBareCacheIfPresent();

        expect(processService.connectivityFsckCount, 1);
      },
    );

    test('rebuilds git cache when bare HEAD points at a tag', () async {
      await _addHiddenAndTagRefs(remoteDir);

      final gitCachePath = p.join(tempDir.path, 'tag_head_cache.git');
      await runGitCommand(['clone', '--mirror', remoteDir.path, gitCachePath]);
      await runGitCommand(
        ['symbolic-ref', 'HEAD', 'refs/tags/test-tag'],
        workingDirectory: gitCachePath,
      );

      final context = FvmContext.create(
        isTest: true,
        configOverrides: AppConfig(
          cachePath: p.join(tempDir.path, '.fvm_tag_head'),
          gitCachePath: gitCachePath,
          flutterUrl: remoteDir.path,
          useGitCache: true,
        ),
      );

      final gitService = GitService(context);
      await gitService.updateLocalMirror();

      await _expectHeadsTagsOnlyCache(gitCachePath);
      final head = await runGitCommand(
        ['symbolic-ref', '--quiet', 'HEAD'],
        workingDirectory: gitCachePath,
      );
      expect(head.stdout.toString().trim(), 'refs/heads/master');
    });

    test(
      'withPreparedGitCacheForClone removes stale pack temp files before clone action',
      () async {
        final gitCachePath = p.join(tempDir.path, 'cache.git');
        final context = FvmContext.create(
          isTest: true,
          configOverrides: AppConfig(
            cachePath: p.join(tempDir.path, '.fvm'),
            gitCachePath: gitCachePath,
            flutterUrl: remoteDir.path,
            useGitCache: true,
          ),
        );

        final gitService = GitService(context);
        await gitService.updateLocalMirror();

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

        await gitService.withPreparedGitCacheForClone(() async {
          for (final file in staleFiles) {
            expect(
              file.existsSync(),
              isFalse,
              reason: 'cleanup runs before clone action',
            );
          }
          expect(freshTemp.existsSync(), isTrue);
          expect(oldNonMatching.existsSync(), isTrue);
        });
      },
    );

    test('removeLocalMirror deletes git cache directory', () async {
      final gitCachePath = p.join(tempDir.path, 'cache.git');
      final context = FvmContext.create(
        isTest: true,
        configOverrides: AppConfig(
          cachePath: p.join(tempDir.path, '.fvm'),
          gitCachePath: gitCachePath,
          flutterUrl: remoteDir.path,
          useGitCache: true,
        ),
      );

      final cacheDir = Directory(gitCachePath)..createSync(recursive: true);
      File(p.join(cacheDir.path, 'marker')).writeAsStringSync('cache');
      expect(cacheDir.existsSync(), isTrue);

      final gitService = GitService(context);
      await expectLater(
          gitService.removeLocalMirror(), throwsA(isA<AppException>()));
      expect(File(p.join(cacheDir.path, 'marker')).readAsStringSync(), 'cache');
      File(p.join(cacheDir.path, 'marker')).deleteSync();
      await gitService.updateLocalMirror();
      final deleted = await gitService.removeLocalMirror();

      expect(deleted, isTrue);
      expect(cacheDir.existsSync(), isFalse);
    });

    test(
      'waits for cache lock before running cache migration checks',
      () async {
        final gitCachePath = p.join(tempDir.path, 'cache.git');
        final lockFilePath = '$gitCachePath.lock';
        final context = FvmContext.create(
          isTest: true,
          configOverrides: AppConfig(
            cachePath: p.join(tempDir.path, '.fvm'),
            gitCachePath: gitCachePath,
            flutterUrl: remoteDir.path,
            useGitCache: true,
          ),
        );

        final lockHelper =
            File(p.join(tempDir.path, 'hold_git_cache_lock.dart'))
              ..writeAsStringSync('''
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
          lockFilePath,
          '1200',
        ]);

        final lockReady = lockProcess.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .firstWhere((line) => line.trim() == 'locked');

        await lockReady.timeout(const Duration(seconds: 5));

        final gitService = GitService(context);
        var completed = false;
        final operation = gitService.ensureBareCacheIfPresent().then((_) {
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
      },
    );

    test(
      'tolerates OS metadata files in refs and reuses the cache without '
      'recreating it (issue #1043)',
      () async {
        final gitCachePath = p.join(tempDir.path, 'ds_store_cache.git');
        final context = FvmContext.create(
          isTest: true,
          configOverrides: AppConfig(
            cachePath: p.join(tempDir.path, '.fvm_ds'),
            gitCachePath: gitCachePath,
            flutterUrl: remoteDir.path,
            useGitCache: true,
          ),
        );

        final gitService = GitService(context);
        await gitService.updateLocalMirror();
        await _expectHeadsTagsOnlyCache(gitCachePath);
        final refsBefore = await _gitRefs(gitCachePath);

        // A marker at the cache root survives an in-place refresh but is lost
        // if the cache is recreated via the atomic directory swap. Its survival
        // proves the cache was reused, not rebuilt from scratch — which is the
        // actual #1043 regression (forced recreation on every `fvm use`).
        final reuseMarker = File(p.join(gitCachePath, '.fvm_reuse_marker'))
          ..writeAsStringSync('reuse');

        // Simulate macOS Finder / Windows Explorer writing metadata into the
        // refs tree — the exact badRefName fsck failure from issue #1043.
        final refsDsStore = File(p.join(gitCachePath, 'refs', '.DS_Store'))
          ..writeAsStringSync('binary junk');
        final headsDsStore =
            File(p.join(gitCachePath, 'refs', 'heads', '.DS_Store'))
              ..writeAsStringSync('binary junk');
        final headsThumbsDb =
            File(p.join(gitCachePath, 'refs', 'heads', 'Thumbs.db'))
              ..writeAsStringSync('junk');

        // Must succeed without recreating the cache.
        await gitService.updateLocalMirror();

        expect(
          reuseMarker.existsSync(),
          isTrue,
          reason: 'cache must be refreshed in place, not recreated',
        );
        expect(refsDsStore.existsSync(), isFalse);
        expect(headsDsStore.existsSync(), isFalse);
        expect(headsThumbsDb.existsSync(), isFalse);
        await _expectHeadsTagsOnlyCache(gitCachePath);
        expect(await _gitRefs(gitCachePath), unorderedEquals(refsBefore));
      },
    );

    test(
      'still detects genuine object corruption and self-heals the cache',
      () async {
        final gitCachePath = p.join(tempDir.path, 'corrupt_cache.git');
        final context = FvmContext.create(
          isTest: true,
          configOverrides: AppConfig(
            cachePath: p.join(tempDir.path, '.fvm_corrupt'),
            gitCachePath: gitCachePath,
            flutterUrl: remoteDir.path,
            useGitCache: true,
          ),
        );

        final gitService = GitService(context);
        await gitService.updateLocalMirror();
        await _expectHeadsTagsOnlyCache(gitCachePath);

        // OS metadata the purge SHOULD remove...
        File(p.join(gitCachePath, 'refs', '.DS_Store'))
            .writeAsStringSync('binary junk');

        // ...alongside genuine corruption the purge must NOT mask: write a ref
        // that points at a non-existent object SHA so that
        // `git fsck --connectivity-only` fails. This is format-agnostic and
        // does not depend on whether git stored objects loose or in packfiles.
        const fakeSha = '0000000000000000000000000000000000000001';
        File(p.join(gitCachePath, 'refs', 'heads', 'corrupt-ref'))
            .writeAsStringSync('$fakeSha\n');

        // Sanity: the corruption is real — fsck now fails.
        final corruptFsck = await Process.run(
          'git',
          ['fsck', '--connectivity-only'],
          workingDirectory: gitCachePath,
          runInShell: true,
        );
        expect(
          corruptFsck.exitCode,
          isNot(0),
          reason: 'a ref pointing at a non-existent object must break fsck',
        );

        // The real `fvm use` path must recover to a verified-healthy cache,
        // proving the metadata purge did not suppress real corruption.
        await gitService.updateLocalMirror();

        final healedFsck = await Process.run(
          'git',
          ['fsck', '--connectivity-only'],
          workingDirectory: gitCachePath,
          runInShell: true,
        );
        expect(
          healedFsck.exitCode,
          0,
          reason: 'cache must self-heal genuine corruption',
        );
        await _expectHeadsTagsOnlyCache(gitCachePath);
      },
    );

    test(
      'resetHard refuses a directory that is not a repository root',
      () async {
        final victimDir = await _createVictimRepository(
          tempDir,
          'victim_reset',
        );
        final nestedDir = Directory(p.join(victimDir.path, 'nested'))
          ..createSync(recursive: true);

        final context = FvmContext.create(
          isTest: true,
          configOverrides: AppConfig(
            cachePath: p.join(tempDir.path, '.fvm_reset'),
            gitCachePath: p.join(tempDir.path, 'reset_cache.git'),
            flutterUrl: remoteDir.path,
            useGitCache: true,
          ),
        );
        final gitService = GitService(context);

        await expectLater(
          gitService.resetHard(nestedDir.path, 'HEAD'),
          throwsA(isA<AppException>()),
        );

        await _expectVictimRepositoryIntact(victimDir);
      },
    );

    test(
      'treats non-repository cache directory inside another repository as '
      'invalid',
      () async {
        final victimDir = await _createVictimRepository(
          tempDir,
          'victim_ancestor',
        );
        // Mirrors e.g. `~/fvm/cache.git` when `$HOME` itself is a git
        // repository: the cache path exists but is not a repository, so git
        // repository discovery walks up to the victim.
        final gitCacheDir =
            Directory(p.join(victimDir.path, 'fvm', 'cache.git'))
              ..createSync(recursive: true);
        File(p.join(gitCacheDir.path, 'junk.txt')).writeAsStringSync('junk');

        final context = FvmContext.create(
          isTest: true,
          configOverrides: AppConfig(
            cachePath: p.join(tempDir.path, '.fvm_ancestor'),
            gitCachePath: gitCacheDir.path,
            flutterUrl: remoteDir.path,
            useGitCache: true,
          ),
        );
        final gitService = GitService(context);

        await expectLater(gitService.ensureBareCacheIfPresent(),
            throwsA(isA<AppException>()));

        await _expectVictimRepositoryIntact(victimDir);
        // Invalid caches are skipped here, not migrated in place.
        expect(File(p.join(gitCacheDir.path, 'junk.txt')).existsSync(), isTrue);

        await expectLater(
            gitService.updateLocalMirror(), throwsA(isA<AppException>()));

        await _expectVictimRepositoryIntact(victimDir);
        expect(gitCacheDir.existsSync(), isTrue);
      },
    );

    test(
      'treats cache directory whose gitfile redirects to another repository '
      'as invalid',
      () async {
        final victimDir = await _createVictimRepository(
          tempDir,
          'victim_gitfile',
        );
        final gitCacheDir = Directory(p.join(tempDir.path, 'gitfile_cache.git'))
          ..createSync(recursive: true);
        File(p.join(gitCacheDir.path, '.git')).writeAsStringSync(
          'gitdir: ${p.join(victimDir.path, '.git')}\n',
        );

        final context = FvmContext.create(
          isTest: true,
          configOverrides: AppConfig(
            cachePath: p.join(tempDir.path, '.fvm_gitfile'),
            gitCachePath: gitCacheDir.path,
            flutterUrl: remoteDir.path,
            useGitCache: true,
          ),
        );
        final gitService = GitService(context);

        await expectLater(gitService.ensureBareCacheIfPresent(),
            throwsA(isA<AppException>()));

        await _expectVictimRepositoryIntact(victimDir);

        await expectLater(
            gitService.updateLocalMirror(), throwsA(isA<AppException>()));

        await _expectVictimRepositoryIntact(victimDir);
        expect(gitCacheDir.existsSync(), isTrue);
      },
    );

    test(
      'treats cache repository whose core.worktree points at another '
      'directory as invalid',
      () async {
        final victimDir = await _createVictimRepository(
          tempDir,
          'victim_worktree',
        );
        final gitCacheDir =
            Directory(p.join(tempDir.path, 'worktree_cache.git'))
              ..createSync(recursive: true);
        await runGitCommand(['init'], workingDirectory: gitCacheDir.path);
        await runGitCommand(
          ['config', 'core.worktree', victimDir.path],
          workingDirectory: gitCacheDir.path,
        );

        final context = FvmContext.create(
          isTest: true,
          configOverrides: AppConfig(
            cachePath: p.join(tempDir.path, '.fvm_worktree'),
            gitCachePath: gitCacheDir.path,
            flutterUrl: remoteDir.path,
            useGitCache: true,
          ),
        );
        final gitService = GitService(context);

        await expectLater(gitService.ensureBareCacheIfPresent(),
            throwsA(isA<AppException>()));

        await _expectVictimRepositoryIntact(victimDir);

        await expectLater(
            gitService.updateLocalMirror(), throwsA(isA<AppException>()));

        await _expectVictimRepositoryIntact(victimDir);
        expect(gitCacheDir.existsSync(), isTrue);
      },
    );
  });
}
