import 'package:dart_mappable/dart_mappable.dart';

import '../../models/cache_flutter_version_model.dart';
import '../../models/cleanup_model.dart';
import '../../models/project_model.dart';
import '../../services/releases_service/models/version_model.dart';
import '../../utils/helpers.dart';
import '../../utils/pretty_json.dart';

part 'json_response.mapper.dart';

typedef JSONMap = Map<String, dynamic>;

@MappableClass(generateMethods: skipCopyWith)
abstract class APIResponse with APIResponseMappable {
  const APIResponse();

  String toPrettyJson() => prettyJson(toMap());
}

@MappableClass()
class GetCacheVersionsResponse extends APIResponse
    with GetCacheVersionsResponseMappable {
  final String size;
  final List<CacheFlutterVersion> versions;

  /// Project roots considered when computing [unreferencedVersions]:
  /// recorded roots that still load as configured FVM projects, plus the
  /// current project when it has a config and is not already in that list.
  final List<String> projects;

  /// Installed versions no project in [projects] pins, excluding the global
  /// one.
  final List<String> unreferencedVersions;

  static final fromMap = GetCacheVersionsResponseMapper.fromMap;
  static final fromJson = GetCacheVersionsResponseMapper.fromJson;

  const GetCacheVersionsResponse({
    required this.size,
    required this.versions,
    required this.projects,
    required this.unreferencedVersions,
  });
}

@MappableClass()
class GetCleanupResponse extends APIResponse with GetCleanupResponseMappable {
  /// Same-line cached patch upgrades. Actions are never applied automatically.
  final List<PatchUpgrade> upgrades;

  /// Unpinned installed names; same membership as
  /// [GetCacheVersionsResponse.unreferencedVersions].
  final List<String> unused;

  /// [unused] minus recommended patch upgrade targets.
  ///
  /// This is the list `fvm cleanup --remove-unused` deletes.
  final List<String> removable;

  static final fromMap = GetCleanupResponseMapper.fromMap;
  static final fromJson = GetCleanupResponseMapper.fromJson;

  const GetCleanupResponse({
    required this.upgrades,
    required this.unused,
    required this.removable,
  });
}

@MappableClass()
class GetReleasesResponse extends APIResponse with GetReleasesResponseMappable {
  /// Channels in Flutter releases
  final Channels channels;

  /// List of all releases
  final List<FlutterSdkRelease> versions;

  static final fromMap = GetReleasesResponseMapper.fromMap;
  static final fromJson = GetReleasesResponseMapper.fromJson;

  const GetReleasesResponse({required this.versions, required this.channels});
}

@MappableClass()
class GetProjectResponse extends APIResponse with GetProjectResponseMappable {
  final Project project;

  static final fromMap = GetProjectResponseMapper.fromMap;
  static final fromJson = GetProjectResponseMapper.fromJson;

  const GetProjectResponse({required this.project});
}

@MappableClass()
class GetContextResponse extends APIResponse with GetContextResponseMappable {
  final Map<String, Object?> context;
  static final fromMap = GetContextResponseMapper.fromMap;
  static final fromJson = GetContextResponseMapper.fromJson;

  const GetContextResponse({required this.context});
}
