import 'dart:io';

import '../services/base_service.dart';
import '../services/cache_service.dart';
import '../services/cleanup_service.dart';
import '../services/project_registry_service.dart';
import '../services/project_service.dart';
import '../services/releases_service/releases_client.dart';
import '../utils/helpers.dart';
import 'models/json_response.dart';

/// Service providing JSON API access to FVM data for integrations and tooling.
class ApiService extends ContextualService {
  const ApiService(super.context);

  /// Returns the current FVM context and configuration.
  GetContextResponse getContext() => GetContextResponse(
        context: {
          'fvmVersion': context.fvmVersion,
          'fvmDir': context.fvmDir,
          'versionsCachePath': context.versionsCachePath,
          'gitCachePath': context.gitCachePath,
          'globalCacheLink': context.globalCacheLink,
          'gitCache': context.gitCache,
          'privilegedAccess': context.privilegedAccess,
        },
      );

  /// Returns project information for the specified directory.
  /// If [projectDir] is null, searches from current directory upward.
  GetProjectResponse getProject([Directory? projectDir]) {
    final project = get<ProjectService>().findAncestor(directory: projectDir);

    return GetProjectResponse(project: project);
  }

  /// Returns all cached Flutter SDK versions with optional size calculation.
  /// Set [skipCacheSizeCalculation] to true for faster response on large caches.
  Future<GetCacheVersionsResponse> getCachedVersions({
    bool skipCacheSizeCalculation = false,
  }) async {
    final versions = await get<CacheService>().getAllVersions();
    final usage = get<ProjectRegistryService>().calculateUsage(
      includeCurrent: get<ProjectService>().tryFindAncestor(),
    );

    var size = 0;
    if (!skipCacheSizeCalculation) {
      final versionSizes = await Future.wait(
        versions.map((version) {
          return getDirectorySize(Directory(version.directory));
        }),
      );
      size = versionSizes.fold<int>(0, (a, b) => a + b);
    }

    return GetCacheVersionsResponse(
      size: formatFriendlyBytes(size),
      versions: versions,
      projects: usage.projectPaths,
      unreferencedVersions: usage.unusedNames([
        for (final version in versions) version.nameWithAlias,
      ]),
    );
  }

  /// Returns cached patch upgrades and unused SDK names.
  Future<GetCleanupResponse> getCleanup() async {
    final plan = await get<CleanupService>().plan();

    return GetCleanupResponse(
      upgrades: plan.upgrades,
      unused: plan.unused,
      removable: plan.removable,
    );
  }

  /// Returns available Flutter SDK releases with optional filtering.
  /// Use [limit] to restrict count and [channelName] to filter by channel.
  Future<GetReleasesResponse> getReleases({
    int? limit,
    String? channelName,
  }) async {
    final payload = await get<FlutterReleaseClient>().fetchReleases();

    var filteredVersions = payload.versions.where((version) {
      if (channelName == null) return true;

      return version.channel.name == channelName;
    });

    if (limit != null) {
      filteredVersions = filteredVersions.take(limit);
    }

    return GetReleasesResponse(
      versions: filteredVersions.toList(),
      channels: payload.channels,
    );
  }
}
