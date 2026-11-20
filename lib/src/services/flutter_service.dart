import 'dart:io';

import 'package:git/git.dart';
import 'package:io/ansi.dart';
import 'package:io/io.dart';
import 'package:path/path.dart' as path;

import '../models/cache_flutter_version_model.dart';
import '../models/flutter_version_model.dart';
import '../utils/context.dart';
import '../utils/exceptions.dart';
import '../utils/file_utils.dart';
import 'base_service.dart';
import 'cache_service.dart';
import 'git_service.dart';
import 'process_service.dart';
import 'releases_service/releases_client.dart';

/// Helpers and tools to interact with Flutter sdk
class FlutterService extends ContextualService {
  static const List<String> _gitObjectCorruptionMarkers = [
    'bad object',
    'loose object',
    'object file',
    'pack has bad object',
  ];

  static const List<String> _gitMissingObjectMarkers = [
    'reference is not a tree',
    'unable to read tree',
    'invalid object name',
    'missing blob',
    'missing tree',
  ];

  static const List<String> _gitObjectErrorPatterns = [
    ..._gitObjectCorruptionMarkers,
    ..._gitMissingObjectMarkers,
  ];

  static const List<String> _gitCorruptionKeywords = [
    'corrupt',
    'damaged',
    'hash mismatch',
  ];

  const FlutterService(super.context);

  Future<ProcessResult> _cloneSdk({
    required String source,
    required Directory versionDir,
    required FlutterVersion version,
    required String? channel,
    required bool echoOutput,
  }) {
    // Pin git's working directory to the clone destination's parent so the
    // process is not sensitive to the global `Directory.current` (which
    // concurrent test cleanup or external callers may have deleted, causing
    // mid-clone "Unable to read current working directory" failures).
    final processCwd = versionDir.parent;
    processCwd.createSync(recursive: true);

    final args = [
      'clone',
      '--progress',
      if (Platform.isWindows) ...['-c', 'core.longpaths=true'],
      if (!version.isUnknownRef && channel != null) ...[
        '-c',
        'advice.detachedHead=false',
        '-b',
        channel,
      ],
      source,
      versionDir.path,
    ];

    return get<ProcessService>().run(
      'git',
      args: args,
      workingDirectory: processCwd.path,
      echoOutput: echoOutput,
    );
  }

  /// Attempts a clone from the local git cache. Returns null on failure so the
  /// caller can fall back to the remote.
  Future<ProcessResult?> _tryCloneFromGitCache({
    required Directory versionDir,
    required FlutterVersion version,
    required String? channel,
    required bool echoOutput,
  }) async {
    try {
      final result =
          await get<GitService>().withPreparedGitCacheForClone(() async {
        return _cloneSdk(
          source: context.gitCachePath,
          versionDir: versionDir,
          version: version,
          channel: channel,
          echoOutput: echoOutput,
        );
      });
      await _updateOriginToFlutter(versionDir);

      return result;
    } on ProcessException catch (error) {
      final isLikelyCorruption = _isGitCacheCorruptionError(error.message);

      if (isLikelyCorruption) {
        logger.warn(
          'Local git cache appears corrupted '
          '(exit ${error.errorCode}: ${error.message}). '
          'Falling back to remote clone.',
        );

        // Non-safety cleanup failures should not abort the remote fallback.
        final cacheDir = Directory(context.gitCachePath);
        if (cacheDir.existsSync()) {
          try {
            final deleted = await get<GitService>().removeLocalMirror(
              requireSuccess: false,
              onFinalError: (error) {
                logger.warn(
                  'Could not remove corrupted cache: ${error.message}. '
                  'You may need to manually delete ${cacheDir.path}',
                );
              },
            );
            if (deleted) {
              logger.info(
                'Removed corrupted cache. It will be recreated on next install.',
              );
            }
          } on GitCacheDependentSdkRemovalException {
            rethrow;
          } catch (e) {
            logger.debug('Failed to remove corrupted git cache: $e');
          }
        }
      } else {
        logger.warn(
          'Cloning from local git cache failed (${error.message}). '
          'Falling back to remote clone.',
        );
      }

      await _cleanupInstallArtifacts(
        version: version,
        versionDir: versionDir,
        removeCache: false,
      );

      return null;
    }
  }

  Future<void> _cleanupPartialClone(Directory versionDir) async {
    if (!versionDir.existsSync()) return;
    await deleteDirectoryWithRetry(
      versionDir,
      requireSuccess: false,
      onFinalError: (e) {
        // Warn level since cleanup failure is recoverable and execution continues
        logger.warn(
          'Unable to clean up partial clone at ${versionDir.path}: ${e.message}. '
          'You may need to manually delete this directory.',
        );
      },
    );
  }

  Future<void> _cleanupInstallArtifacts({
    required FlutterVersion version,
    required Directory versionDir,
    required bool removeCache,
  }) async {
    await _cleanupPartialClone(versionDir);

    if (removeCache) {
      await get<CacheService>().remove(version);
    }
  }

  Future<void> _updateOriginToFlutter(Directory versionDir) async {
    await get<GitService>().setOriginUrl(
      repositoryPath: versionDir.path,
      url: context.flutterUrl,
    );
  }

  /// Detects git errors indicating a reference (branch/tag/commit) doesn't exist.
  /// Used to determine if retry from remote is warranted.
  bool _isReferenceLookupError(String errorMessage) {
    final lower = errorMessage.toLowerCase();

    return lower.contains('unknown revision') ||
        lower.contains('ambiguous argument') ||
        lower.contains('could not parse object') ||
        (lower.contains('pathspec') && lower.contains('did not match'));
  }

  /// Detects git errors that indicate missing or unreadable objects in the
  /// local git cache. These should trigger a retry from the remote.
  bool _isMissingObjectError(String errorMessage) {
    final lower = errorMessage.toLowerCase();

    return _gitObjectErrorPatterns.any(lower.contains);
  }

  bool _isGitCacheCorruptionError(String errorMessage) {
    final lower = errorMessage.toLowerCase();

    return _gitCorruptionKeywords.any(lower.contains) ||
        _gitObjectCorruptionMarkers.any(lower.contains);
  }

  Never _throwReferenceLookupError({
    required FlutterVersion version,
    required String repoUrl,
    required StackTrace stackTrace,
  }) {
    final message = version.fromFork
        ? 'Reference "${version.version}" was not found in fork "${version.fork}".\n'
            'Please verify that this version exists in the forked repository.\n'
            'Repository URL: $repoUrl'
        : 'Reference "${version.version}" was not found in the Flutter repository.\n'
            'Please check that you have specified a valid version.\n'
            'Repository URL: $repoUrl';

    Error.throwWithStackTrace(AppException(message), stackTrace);
  }

  Future<void> _retryInstallFromRemote({
    required FlutterVersion version,
    required Directory versionDir,
    required String repoUrl,
    required String? channel,
    required bool echoOutput,
  }) async {
    logger.warn(
      'Reference "${version.version}" not found in local git cache. '
      'Retrying clone from remote repository...',
    );

    await _cleanupInstallArtifacts(
      version: version,
      versionDir: versionDir,
      removeCache: false,
    );

    final retryResult = await _cloneSdk(
      source: repoUrl,
      versionDir: versionDir,
      version: version,
      channel: channel,
      echoOutput: echoOutput,
    );

    if (retryResult.exitCode != ExitCode.success.code) {
      throw AppException(
        'Could not clone Flutter SDK: ${cyan.wrap(version.printFriendlyName)}',
      );
    }

    // Validate reference in fresh clone (no retry this time)
    try {
      await _ensureReference(version: version, gitVersionDir: versionDir);
    } on ProcessException catch (error, stackTrace) {
      if (_isReferenceLookupError(error.message)) {
        _throwReferenceLookupError(
          version: version,
          repoUrl: repoUrl,
          stackTrace: stackTrace,
        );
      }
      rethrow;
    }

    // Bring the shared git cache up to date so future installs can use it.
    if (context.gitCache && !version.fromFork) {
      try {
        await get<GitService>().updateLocalMirror();
      } catch (e, stackTrace) {
        logger.debug('Git cache refresh after fallback failed: $e');
        logger.warn(
          'Failed to refresh local git cache after remote clone; continuing. '
          'This may cause the next install to fetch from remote again.',
        );
        logger.debug(stackTrace.toString());
      }
    }
  }

  Future<void> _ensureReference({
    required FlutterVersion version,
    required Directory gitVersionDir,
  }) async {
    final processService = get<ProcessService>();

    // Check if version is a remote branch
    final branchResult = await processService.run(
      'git',
      args: ['branch', '-r', '--list', 'origin/${version.version}'],
      workingDirectory: gitVersionDir.path,
    );

    final isBranch = (branchResult.stdout as String).trim().isNotEmpty;

    if (isBranch) {
      await get<GitService>().verifyWorkingTreeRoot(gitVersionDir.path);
      await processService.run(
        'git',
        args: ['checkout', version.version],
        workingDirectory: gitVersionDir.path,
      );
      logger.debug('Checked out branch: ${version.version}');
    } else {
      await get<GitService>().resetHard(gitVersionDir.path, version.version);
    }
  }

  Directory _setupCacheDirectories(FlutterVersion version) {
    final versionDir = get<CacheService>().getVersionCacheDir(version);

    if (version.fromFork) {
      Directory(path.join(context.versionsCachePath, version.fork!))
          .createSync(recursive: true);
    }

    return versionDir;
  }

  Future<String?> _resolveChannel(FlutterVersion version) async {
    if (version.isChannel) return version.name;

    if (version.isRelease) {
      if (version.releaseChannel != null) {
        return version.releaseChannel!.name;
      }

      final release = await get<FlutterReleaseClient>().getReleaseByVersion(
        version.name,
      );

      if (release != null) return release.channel.name;
    }

    return version.name;
  }

  String _resolveRepositoryUrl(FlutterVersion version) {
    String repoUrl = context.flutterUrl;

    if (version.fromFork) {
      logger.debug('Installing from fork: ${version.fork}');

      try {
        repoUrl = context.getForkUrl(version.fork!);
        logger.info('Using forked repository URL: $repoUrl');
      } catch (_, stackTrace) {
        Error.throwWithStackTrace(
          AppException(
            'Fork "${version.fork}" not found in configuration. '
            'Please add it first using: fvm fork add ${version.fork} <url>',
          ),
          stackTrace,
        );
      }
    }

    return repoUrl;
  }

  /// Clones the SDK, trying the local git cache first when enabled.
  /// Returns true if the clone came from the local git cache.
  Future<bool> _executeClone({
    required FlutterVersion version,
    required Directory versionDir,
    required String repoUrl,
    required String? channel,
    required bool echoOutput,
    required bool useGitCache,
  }) async {
    final useLocalGitCache =
        useGitCache && context.gitCache && !version.fromFork;

    if (useLocalGitCache) {
      final gitCacheResult = await _tryCloneFromGitCache(
        versionDir: versionDir,
        version: version,
        channel: channel,
        echoOutput: echoOutput,
      );

      if (gitCacheResult != null) return true;
    }

    await _cloneSdk(
      source: repoUrl,
      versionDir: versionDir,
      version: version,
      channel: channel,
      echoOutput: echoOutput,
    );

    return false;
  }

  Future<void> _validateReference({
    required FlutterVersion version,
    required Directory versionDir,
    required bool clonedFromGitCache,
    required String repoUrl,
    required String? channel,
    required bool echoOutput,
  }) async {
    if (version.isChannel) return;

    try {
      await _ensureReference(version: version, gitVersionDir: versionDir);
    } on ProcessException catch (e, stackTrace) {
      final isReferenceError = _isReferenceLookupError(e.message);
      final isMissingObject = _isMissingObjectError(e.message);

      if (clonedFromGitCache && (isReferenceError || isMissingObject)) {
        await _retryInstallFromRemote(
          version: version,
          versionDir: versionDir,
          repoUrl: repoUrl,
          channel: channel,
          echoOutput: echoOutput,
        );
      } else if (isReferenceError) {
        _throwReferenceLookupError(
          version: version,
          repoUrl: repoUrl,
          stackTrace: stackTrace,
        );
      } else {
        rethrow;
      }
    }
  }

  Future<void> _handleCloneError({
    required Object error,
    required StackTrace stackTrace,
    required FlutterVersion version,
    required Directory versionDir,
    required String repoUrl,
  }) async {
    // Best-effort cleanup — must not mask the original error.
    try {
      await _cleanupInstallArtifacts(
        version: version,
        versionDir: versionDir,
        removeCache: true,
      );
    } catch (cleanupError) {
      logger.debug('Cleanup after install failure failed: $cleanupError');
    }

    if (error is ProcessException) {
      final errorMessage = error.toString().toLowerCase();

      if (errorMessage.contains('repository not found') ||
          (errorMessage.contains('remote branch') &&
              errorMessage.contains('not found'))) {
        if (version.fromFork) {
          Error.throwWithStackTrace(
            AppException(
              'Failed to clone fork "${version.fork}" with version "${version.version}".\n'
              'Please verify that the fork URL is correct and the version exists.\n'
              'Repository URL: $repoUrl',
            ),
            stackTrace,
          );
        }

        Error.throwWithStackTrace(
          AppException(
            'Failed to clone Flutter repository with version "${version.version}".\n'
            'The branch or tag does not exist in the upstream repository.\n'
            'Repository URL: $repoUrl',
          ),
          stackTrace,
        );
      }
    }

    if (error is AppException) {
      Error.throwWithStackTrace(error, stackTrace);
    }

    logger.debug('Clone error details: $error');
    Error.throwWithStackTrace(
      AppException(
        'Failed to install Flutter SDK: ${version.printFriendlyName}.\n'
        'Run with --verbose for more details.',
      ),
      stackTrace,
    );
  }

  Future<ProcessResult> run(
    String cmd,
    List<String> args,
    CacheFlutterVersion version, {
    bool throwOnError = false,
    bool? echoOutput,
  }) {
    final versionRunner = VersionRunner(context: context, version: version);

    return versionRunner.run(
      cmd,
      args,
      throwOnError: throwOnError,
      echoOutput: echoOutput,
    );
  }

  Future<ProcessResult> pubGet(
    CacheFlutterVersion version, {
    bool throwOnError = false,
    bool offline = false,
  }) {
    final args = ['pub', 'get', if (offline) '--offline'];

    // Online mode needs stdio inheritance for authentication prompts
    return run(
      'flutter',
      args,
      version,
      throwOnError: throwOnError,
      echoOutput: !offline,
    );
  }

  Future<ProcessResult> setup(CacheFlutterVersion version) {
    return run('flutter', ['--version'], version);
  }

  Future<ProcessResult> runFlutter(
    List<String> args,
    CacheFlutterVersion version,
  ) {
    return run('flutter', args, version);
  }

  Future<void> install(
    FlutterVersion version, {
    bool useGitCache = true,
  }) async {
    final versionDir = _setupCacheDirectories(version);
    final channel = await _resolveChannel(version);
    final repoUrl = _resolveRepositoryUrl(version);
    final echoOutput = !context.isTest && logger.isVerbose;

    try {
      final clonedFromGitCache = await _executeClone(
        version: version,
        versionDir: versionDir,
        repoUrl: repoUrl,
        channel: channel,
        echoOutput: echoOutput,
        useGitCache: useGitCache,
      );

      final isGit = await GitDir.isGitDir(versionDir.path);
      if (!isGit) {
        throw AppException(
          'Flutter SDK is not a valid git repository after clone. Please try again.',
        );
      }

      await _validateReference(
        version: version,
        versionDir: versionDir,
        clonedFromGitCache: clonedFromGitCache,
        repoUrl: repoUrl,
        channel: channel,
        echoOutput: echoOutput,
      );
    } catch (error, stackTrace) {
      await _handleCloneError(
        error: error,
        stackTrace: stackTrace,
        version: version,
        versionDir: versionDir,
        repoUrl: repoUrl,
      );
    }
  }
}

class VersionRunner {
  final FvmContext _context;
  final CacheFlutterVersion _version;

  const VersionRunner({
    required FvmContext context,
    required CacheFlutterVersion version,
  })  : _context = context,
        _version = version;

  Map<String, String> _updateEnvironmentVariables(List<String> paths) {
    final uniquePaths = paths.toSet().toList();
    final env = _context.environment;
    final separator = Platform.isWindows ? ';' : ':';

    return {
      ...env,
      'PATH': uniquePaths.join(separator) + separator + (env['PATH'] ?? ''),
    };
  }

  Future<ProcessResult> run(
    String cmd,
    List<String> args, {
    bool? echoOutput,
    bool? throwOnError,
  }) {
    // Bind SDK commands before crossing the process boundary. In particular,
    // Windows searches the current directory before PATH during shell lookup.
    final sdkExecutable = switch (cmd) {
      'flutter' => path.absolute(_version.flutterExec),
      'dart' => path.absolute(_version.dartExec),
      _ => null,
    };
    final environment = _updateEnvironmentVariables([
      _version.binPath,
      _version.dartBinPath,
    ]);

    return _context.get<ProcessService>().run(
          sdkExecutable ?? cmd,
          args: args,
          environment: environment,
          throwOnError: throwOnError ?? false,
          echoOutput: echoOutput ?? true,
          runInShell: sdkExecutable == null,
        );
  }
}
