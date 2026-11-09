import 'dart:io';

import 'package:mason_logger/mason_logger.dart';

import '../models/cache_flutter_version_model.dart';
import '../models/flutter_version_model.dart';
import '../services/cache_service.dart';
import '../services/flutter_service.dart';
import '../services/git_service.dart';
import '../utils/exceptions.dart';
import '../utils/helpers.dart';
import 'workflow.dart';

class EnsureCacheWorkflow extends Workflow {
  const EnsureCacheWorkflow(super.context);

  Future<CacheFlutterVersion> _handleNonExecutable(
    CacheFlutterVersion version, {
    required bool shouldInstall,
    required bool force,
    int retryCount = 0,
  }) async {
    const maxRetries = 2;
    if (retryCount >= maxRetries) {
      throw AppException(
        'Failed to fix corrupted cache after $maxRetries attempts. '
        'Please check disk space and permissions, then try again.',
      );
    }

    logger
      ..notice(
        'Flutter SDK version: ${version.name} isn\'t executable, indicating the cache is corrupted.',
      )
      ..info(
        'Auto-fixing corrupted cache by reinstalling (attempt ${retryCount + 1}/$maxRetries)...',
      );

    await get<CacheService>().remove(version);
    logger.info('Removing corrupted SDK and reinstalling...');

    return await call(
      version,
      shouldInstall: shouldInstall,
      force: force,
      retryCount: retryCount + 1,
    );
  }

  Future<CacheFlutterVersion> _handleVersionMismatch(
    CacheFlutterVersion version,
  ) async {
    logger
      ..notice(
        'Cached SDK metadata reports ${version.flutterSdkVersion}, but FVM expected ${version.name} for this cache entry.',
      )
      ..info(
        'This can happen when a cached SDK is upgraded or changed outside FVM.',
      )
      ..info();

    final firstOption =
        'Move ${version.flutterSdkVersion} to the correct cache directory and reinstall ${version.name}';

    final secondOption =
        'Remove incorrect version and reinstall ${version.name}';

    String selectedOption;
    if (context.skipInput) {
      logger.warn(
        'CI/non-interactive mode: auto-selecting remove and reinstall',
      );
      selectedOption = secondOption;
    } else {
      selectedOption = logger.select(
        'How would you like to resolve this?',
        options: [firstOption, secondOption],
      );
    }

    if (selectedOption == firstOption) {
      logger.info('Moving SDK to the correct cache directory...');
      get<CacheService>().moveToSdkVersionDirectory(version);
    }

    logger.info('Removing incorrect SDK version...');
    await get<CacheService>().remove(version);

    return await call(version, shouldInstall: true);
  }

  void _validateContext() {
    if (!isValidGitUrl(context.flutterUrl)) {
      throw AppException(
        'Invalid Flutter URL: "${context.flutterUrl}". '
        'Please change config to a valid git url',
      );
    }
  }

  void _validateGit() {
    try {
      final result = Process.runSync('git', ['--version']);
      if (result.exitCode != 0) {
        throw const AppException('Git is not installed');
      }
    } on ProcessException catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const AppException('Git is not installed'),
        stackTrace,
      );
    }
  }

  /// Ensures that the specified Flutter SDK version is cached locally.
  ///
  /// Returns a [CacheFlutterVersion] which represents the locally cached version.
  ///
  /// When [maintainGitCacheOnHit] is false, an already-installed SDK leaves the
  /// shared git cache unchanged. Legacy migration, shape checks, and
  /// connectivity validation are deferred until a maintenance caller or cache
  /// miss prepares the git cache for installation.
  Future<CacheFlutterVersion> call(
    FlutterVersion version, {
    bool shouldInstall = false,
    bool force = false,
    int retryCount = 0,
    bool maintainGitCacheOnHit = true,
  }) async {
    _validateContext();
    _validateGit();
    // Get valid flutter version
    final cacheService = get<CacheService>();
    final flutterService = get<FlutterService>();
    final gitService = get<GitService>();

    var cacheVersion = cacheService.getVersion(version);

    // Migrate legacy non-bare caches if present.
    // Refresh the git cache only when we actually need to clone (cache miss).
    final useGitCache = context.gitCache;
    var useGitCacheForInstall = useGitCache;
    final shouldPrepareGitCache = maintainGitCacheOnHit || cacheVersion == null;
    if (shouldPrepareGitCache && !version.fromFork) {
      try {
        await gitService.ensureBareCacheIfPresent();
        cacheVersion = cacheService.getVersion(version);
        if (useGitCache && cacheVersion == null) {
          await gitService.updateLocalMirror();
          cacheVersion = cacheService.getVersion(version);
        }
      } on GitCacheDependentSdkRemovalException {
        rethrow;
      } on Exception catch (e) {
        useGitCacheForInstall = false;
        logger.debug('Local cache setup exception: $e');
        logger.warn('Failed to setup local cache. Falling back to git clone.');
      }
    }

    if (cacheVersion != null) {
      final integrity = await cacheService.verifyCacheIntegrity(cacheVersion);

      if (integrity == CacheIntegrity.invalid) {
        return await _handleNonExecutable(
          cacheVersion,
          shouldInstall: shouldInstall,
          force: force,
          retryCount: retryCount,
        );
      }

      if (integrity == CacheIntegrity.versionMismatch &&
          !force &&
          !version.isCustom) {
        return await _handleVersionMismatch(cacheVersion);
      } else if (force) {
        logger.warn(
          'Not checking for version mismatch as --force flag is set.',
        );
      } else if (version.isCustom) {
        logger.debug(
          'Not checking for version mismatch as local version is being used.',
        );
      }

      // If should install notify the user that is already installed
      if (shouldInstall) {
        logger.success(
          'Flutter SDK: ${cyan.wrap(cacheVersion.printFriendlyName)} is already installed.',
        );
      }

      return cacheVersion;
    }

    if (version.isCustom) {
      throw AppException('Local Flutter SDKs must be installed manually.');
    }

    if (!shouldInstall) {
      logger.info(
        'Flutter SDK: ${cyan.wrap(version.printFriendlyName)} is not installed.',
      );
      logger.info('Installing Flutter SDK automatically...');
    }

    final progress = logger.progress(
      'Installing Flutter SDK: ${cyan.wrap(version.printFriendlyName)}',
    );
    try {
      await flutterService.install(version, useGitCache: useGitCacheForInstall);

      progress.complete(
        'Flutter SDK: ${cyan.wrap(version.printFriendlyName)} installed!',
      );
    } on Exception {
      progress.fail('Failed to install ${version.name}');
      rethrow;
    }

    final newCacheVersion = cacheService.getVersion(version);
    if (newCacheVersion == null) {
      throw AppException('Could not verify cache version $version');
    }

    return newCacheVersion;
  }
}
