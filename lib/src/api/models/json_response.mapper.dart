// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'json_response.dart';

class APIResponseMapper extends ClassMapperBase<APIResponse> {
  APIResponseMapper._();

  static APIResponseMapper? _instance;
  static APIResponseMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = APIResponseMapper._());
      GetCacheVersionsResponseMapper.ensureInitialized();
      GetCleanupResponseMapper.ensureInitialized();
      GetReleasesResponseMapper.ensureInitialized();
      GetProjectResponseMapper.ensureInitialized();
      GetContextResponseMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'APIResponse';

  @override
  final MappableFields<APIResponse> fields = const {};

  static APIResponse _instantiate(DecodingData data) {
    throw MapperException.missingConstructor('APIResponse');
  }

  @override
  final Function instantiate = _instantiate;

  static APIResponse fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<APIResponse>(map);
  }

  static APIResponse fromJson(String json) {
    return ensureInitialized().decodeJson<APIResponse>(json);
  }
}

mixin APIResponseMappable {
  String toJson();
  Map<String, dynamic> toMap();
}

class GetCacheVersionsResponseMapper
    extends ClassMapperBase<GetCacheVersionsResponse> {
  GetCacheVersionsResponseMapper._();

  static GetCacheVersionsResponseMapper? _instance;
  static GetCacheVersionsResponseMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals
          .use(_instance = GetCacheVersionsResponseMapper._());
      APIResponseMapper.ensureInitialized();
      CacheFlutterVersionMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'GetCacheVersionsResponse';

  static String _$size(GetCacheVersionsResponse v) => v.size;
  static const Field<GetCacheVersionsResponse, String> _f$size =
      Field('size', _$size);
  static List<CacheFlutterVersion> _$versions(GetCacheVersionsResponse v) =>
      v.versions;
  static const Field<GetCacheVersionsResponse, List<CacheFlutterVersion>>
      _f$versions = Field('versions', _$versions);
  static List<String> _$projects(GetCacheVersionsResponse v) => v.projects;
  static const Field<GetCacheVersionsResponse, List<String>> _f$projects =
      Field('projects', _$projects);
  static List<String> _$unreferencedVersions(GetCacheVersionsResponse v) =>
      v.unreferencedVersions;
  static const Field<GetCacheVersionsResponse, List<String>>
      _f$unreferencedVersions =
      Field('unreferencedVersions', _$unreferencedVersions);

  @override
  final MappableFields<GetCacheVersionsResponse> fields = const {
    #size: _f$size,
    #versions: _f$versions,
    #projects: _f$projects,
    #unreferencedVersions: _f$unreferencedVersions,
  };

  static GetCacheVersionsResponse _instantiate(DecodingData data) {
    return GetCacheVersionsResponse(
        size: data.dec(_f$size),
        versions: data.dec(_f$versions),
        projects: data.dec(_f$projects),
        unreferencedVersions: data.dec(_f$unreferencedVersions));
  }

  @override
  final Function instantiate = _instantiate;

  static GetCacheVersionsResponse fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GetCacheVersionsResponse>(map);
  }

  static GetCacheVersionsResponse fromJson(String json) {
    return ensureInitialized().decodeJson<GetCacheVersionsResponse>(json);
  }
}

mixin GetCacheVersionsResponseMappable {
  String toJson() {
    return GetCacheVersionsResponseMapper.ensureInitialized()
        .encodeJson<GetCacheVersionsResponse>(this as GetCacheVersionsResponse);
  }

  Map<String, dynamic> toMap() {
    return GetCacheVersionsResponseMapper.ensureInitialized()
        .encodeMap<GetCacheVersionsResponse>(this as GetCacheVersionsResponse);
  }

  GetCacheVersionsResponseCopyWith<GetCacheVersionsResponse,
          GetCacheVersionsResponse, GetCacheVersionsResponse>
      get copyWith => _GetCacheVersionsResponseCopyWithImpl<
              GetCacheVersionsResponse, GetCacheVersionsResponse>(
          this as GetCacheVersionsResponse, $identity, $identity);
  @override
  String toString() {
    return GetCacheVersionsResponseMapper.ensureInitialized()
        .stringifyValue(this as GetCacheVersionsResponse);
  }

  @override
  bool operator ==(Object other) {
    return GetCacheVersionsResponseMapper.ensureInitialized()
        .equalsValue(this as GetCacheVersionsResponse, other);
  }

  @override
  int get hashCode {
    return GetCacheVersionsResponseMapper.ensureInitialized()
        .hashValue(this as GetCacheVersionsResponse);
  }
}

extension GetCacheVersionsResponseValueCopy<$R, $Out>
    on ObjectCopyWith<$R, GetCacheVersionsResponse, $Out> {
  GetCacheVersionsResponseCopyWith<$R, GetCacheVersionsResponse, $Out>
      get $asGetCacheVersionsResponse => $base.as((v, t, t2) =>
          _GetCacheVersionsResponseCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class GetCacheVersionsResponseCopyWith<
    $R,
    $In extends GetCacheVersionsResponse,
    $Out> implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
      $R,
      CacheFlutterVersion,
      CacheFlutterVersionCopyWith<$R, CacheFlutterVersion,
          CacheFlutterVersion>> get versions;
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get projects;
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
      get unreferencedVersions;
  $R call(
      {String? size,
      List<CacheFlutterVersion>? versions,
      List<String>? projects,
      List<String>? unreferencedVersions});
  GetCacheVersionsResponseCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
      Then<$Out2, $R2> t);
}

class _GetCacheVersionsResponseCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, GetCacheVersionsResponse, $Out>
    implements
        GetCacheVersionsResponseCopyWith<$R, GetCacheVersionsResponse, $Out> {
  _GetCacheVersionsResponseCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<GetCacheVersionsResponse> $mapper =
      GetCacheVersionsResponseMapper.ensureInitialized();
  @override
  ListCopyWith<
      $R,
      CacheFlutterVersion,
      CacheFlutterVersionCopyWith<$R, CacheFlutterVersion,
          CacheFlutterVersion>> get versions => ListCopyWith($value.versions,
      (v, t) => v.copyWith.$chain(t), (v) => call(versions: v));
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get projects =>
      ListCopyWith($value.projects, (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(projects: v));
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
      get unreferencedVersions => ListCopyWith(
          $value.unreferencedVersions,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(unreferencedVersions: v));
  @override
  $R call(
          {String? size,
          List<CacheFlutterVersion>? versions,
          List<String>? projects,
          List<String>? unreferencedVersions}) =>
      $apply(FieldCopyWithData({
        if (size != null) #size: size,
        if (versions != null) #versions: versions,
        if (projects != null) #projects: projects,
        if (unreferencedVersions != null)
          #unreferencedVersions: unreferencedVersions
      }));
  @override
  GetCacheVersionsResponse $make(CopyWithData data) => GetCacheVersionsResponse(
      size: data.get(#size, or: $value.size),
      versions: data.get(#versions, or: $value.versions),
      projects: data.get(#projects, or: $value.projects),
      unreferencedVersions:
          data.get(#unreferencedVersions, or: $value.unreferencedVersions));

  @override
  GetCacheVersionsResponseCopyWith<$R2, GetCacheVersionsResponse, $Out2>
      $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
          _GetCacheVersionsResponseCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class GetCleanupResponseMapper extends ClassMapperBase<GetCleanupResponse> {
  GetCleanupResponseMapper._();

  static GetCleanupResponseMapper? _instance;
  static GetCleanupResponseMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GetCleanupResponseMapper._());
      APIResponseMapper.ensureInitialized();
      PatchUpgradeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'GetCleanupResponse';

  static List<PatchUpgrade> _$upgrades(GetCleanupResponse v) => v.upgrades;
  static const Field<GetCleanupResponse, List<PatchUpgrade>> _f$upgrades =
      Field('upgrades', _$upgrades);
  static List<String> _$unused(GetCleanupResponse v) => v.unused;
  static const Field<GetCleanupResponse, List<String>> _f$unused =
      Field('unused', _$unused);
  static List<String> _$removable(GetCleanupResponse v) => v.removable;
  static const Field<GetCleanupResponse, List<String>> _f$removable =
      Field('removable', _$removable);

  @override
  final MappableFields<GetCleanupResponse> fields = const {
    #upgrades: _f$upgrades,
    #unused: _f$unused,
    #removable: _f$removable,
  };

  static GetCleanupResponse _instantiate(DecodingData data) {
    return GetCleanupResponse(
        upgrades: data.dec(_f$upgrades),
        unused: data.dec(_f$unused),
        removable: data.dec(_f$removable));
  }

  @override
  final Function instantiate = _instantiate;

  static GetCleanupResponse fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GetCleanupResponse>(map);
  }

  static GetCleanupResponse fromJson(String json) {
    return ensureInitialized().decodeJson<GetCleanupResponse>(json);
  }
}

mixin GetCleanupResponseMappable {
  String toJson() {
    return GetCleanupResponseMapper.ensureInitialized()
        .encodeJson<GetCleanupResponse>(this as GetCleanupResponse);
  }

  Map<String, dynamic> toMap() {
    return GetCleanupResponseMapper.ensureInitialized()
        .encodeMap<GetCleanupResponse>(this as GetCleanupResponse);
  }

  GetCleanupResponseCopyWith<GetCleanupResponse, GetCleanupResponse,
          GetCleanupResponse>
      get copyWith => _GetCleanupResponseCopyWithImpl<GetCleanupResponse,
          GetCleanupResponse>(this as GetCleanupResponse, $identity, $identity);
  @override
  String toString() {
    return GetCleanupResponseMapper.ensureInitialized()
        .stringifyValue(this as GetCleanupResponse);
  }

  @override
  bool operator ==(Object other) {
    return GetCleanupResponseMapper.ensureInitialized()
        .equalsValue(this as GetCleanupResponse, other);
  }

  @override
  int get hashCode {
    return GetCleanupResponseMapper.ensureInitialized()
        .hashValue(this as GetCleanupResponse);
  }
}

extension GetCleanupResponseValueCopy<$R, $Out>
    on ObjectCopyWith<$R, GetCleanupResponse, $Out> {
  GetCleanupResponseCopyWith<$R, GetCleanupResponse, $Out>
      get $asGetCleanupResponse => $base.as(
          (v, t, t2) => _GetCleanupResponseCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class GetCleanupResponseCopyWith<$R, $In extends GetCleanupResponse,
    $Out> implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, PatchUpgrade,
      PatchUpgradeCopyWith<$R, PatchUpgrade, PatchUpgrade>> get upgrades;
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get unused;
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get removable;
  $R call(
      {List<PatchUpgrade>? upgrades,
      List<String>? unused,
      List<String>? removable});
  GetCleanupResponseCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
      Then<$Out2, $R2> t);
}

class _GetCleanupResponseCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, GetCleanupResponse, $Out>
    implements GetCleanupResponseCopyWith<$R, GetCleanupResponse, $Out> {
  _GetCleanupResponseCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<GetCleanupResponse> $mapper =
      GetCleanupResponseMapper.ensureInitialized();
  @override
  ListCopyWith<$R, PatchUpgrade,
          PatchUpgradeCopyWith<$R, PatchUpgrade, PatchUpgrade>>
      get upgrades => ListCopyWith($value.upgrades,
          (v, t) => v.copyWith.$chain(t), (v) => call(upgrades: v));
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get unused =>
      ListCopyWith($value.unused, (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(unused: v));
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get removable =>
      ListCopyWith($value.removable, (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(removable: v));
  @override
  $R call(
          {List<PatchUpgrade>? upgrades,
          List<String>? unused,
          List<String>? removable}) =>
      $apply(FieldCopyWithData({
        if (upgrades != null) #upgrades: upgrades,
        if (unused != null) #unused: unused,
        if (removable != null) #removable: removable
      }));
  @override
  GetCleanupResponse $make(CopyWithData data) => GetCleanupResponse(
      upgrades: data.get(#upgrades, or: $value.upgrades),
      unused: data.get(#unused, or: $value.unused),
      removable: data.get(#removable, or: $value.removable));

  @override
  GetCleanupResponseCopyWith<$R2, GetCleanupResponse, $Out2> $chain<$R2, $Out2>(
          Then<$Out2, $R2> t) =>
      _GetCleanupResponseCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class GetReleasesResponseMapper extends ClassMapperBase<GetReleasesResponse> {
  GetReleasesResponseMapper._();

  static GetReleasesResponseMapper? _instance;
  static GetReleasesResponseMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GetReleasesResponseMapper._());
      APIResponseMapper.ensureInitialized();
      FlutterSdkReleaseMapper.ensureInitialized();
      ChannelsMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'GetReleasesResponse';

  static List<FlutterSdkRelease> _$versions(GetReleasesResponse v) =>
      v.versions;
  static const Field<GetReleasesResponse, List<FlutterSdkRelease>> _f$versions =
      Field('versions', _$versions);
  static Channels _$channels(GetReleasesResponse v) => v.channels;
  static const Field<GetReleasesResponse, Channels> _f$channels =
      Field('channels', _$channels);

  @override
  final MappableFields<GetReleasesResponse> fields = const {
    #versions: _f$versions,
    #channels: _f$channels,
  };

  static GetReleasesResponse _instantiate(DecodingData data) {
    return GetReleasesResponse(
        versions: data.dec(_f$versions), channels: data.dec(_f$channels));
  }

  @override
  final Function instantiate = _instantiate;

  static GetReleasesResponse fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GetReleasesResponse>(map);
  }

  static GetReleasesResponse fromJson(String json) {
    return ensureInitialized().decodeJson<GetReleasesResponse>(json);
  }
}

mixin GetReleasesResponseMappable {
  String toJson() {
    return GetReleasesResponseMapper.ensureInitialized()
        .encodeJson<GetReleasesResponse>(this as GetReleasesResponse);
  }

  Map<String, dynamic> toMap() {
    return GetReleasesResponseMapper.ensureInitialized()
        .encodeMap<GetReleasesResponse>(this as GetReleasesResponse);
  }

  GetReleasesResponseCopyWith<GetReleasesResponse, GetReleasesResponse,
      GetReleasesResponse> get copyWith => _GetReleasesResponseCopyWithImpl<
          GetReleasesResponse, GetReleasesResponse>(
      this as GetReleasesResponse, $identity, $identity);
  @override
  String toString() {
    return GetReleasesResponseMapper.ensureInitialized()
        .stringifyValue(this as GetReleasesResponse);
  }

  @override
  bool operator ==(Object other) {
    return GetReleasesResponseMapper.ensureInitialized()
        .equalsValue(this as GetReleasesResponse, other);
  }

  @override
  int get hashCode {
    return GetReleasesResponseMapper.ensureInitialized()
        .hashValue(this as GetReleasesResponse);
  }
}

extension GetReleasesResponseValueCopy<$R, $Out>
    on ObjectCopyWith<$R, GetReleasesResponse, $Out> {
  GetReleasesResponseCopyWith<$R, GetReleasesResponse, $Out>
      get $asGetReleasesResponse => $base.as(
          (v, t, t2) => _GetReleasesResponseCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class GetReleasesResponseCopyWith<$R, $In extends GetReleasesResponse,
    $Out> implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, FlutterSdkRelease,
          FlutterSdkReleaseCopyWith<$R, FlutterSdkRelease, FlutterSdkRelease>>
      get versions;
  ChannelsCopyWith<$R, Channels, Channels> get channels;
  $R call({List<FlutterSdkRelease>? versions, Channels? channels});
  GetReleasesResponseCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
      Then<$Out2, $R2> t);
}

class _GetReleasesResponseCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, GetReleasesResponse, $Out>
    implements GetReleasesResponseCopyWith<$R, GetReleasesResponse, $Out> {
  _GetReleasesResponseCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<GetReleasesResponse> $mapper =
      GetReleasesResponseMapper.ensureInitialized();
  @override
  ListCopyWith<$R, FlutterSdkRelease,
          FlutterSdkReleaseCopyWith<$R, FlutterSdkRelease, FlutterSdkRelease>>
      get versions => ListCopyWith($value.versions,
          (v, t) => v.copyWith.$chain(t), (v) => call(versions: v));
  @override
  ChannelsCopyWith<$R, Channels, Channels> get channels =>
      $value.channels.copyWith.$chain((v) => call(channels: v));
  @override
  $R call({List<FlutterSdkRelease>? versions, Channels? channels}) =>
      $apply(FieldCopyWithData({
        if (versions != null) #versions: versions,
        if (channels != null) #channels: channels
      }));
  @override
  GetReleasesResponse $make(CopyWithData data) => GetReleasesResponse(
      versions: data.get(#versions, or: $value.versions),
      channels: data.get(#channels, or: $value.channels));

  @override
  GetReleasesResponseCopyWith<$R2, GetReleasesResponse, $Out2>
      $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
          _GetReleasesResponseCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class GetProjectResponseMapper extends ClassMapperBase<GetProjectResponse> {
  GetProjectResponseMapper._();

  static GetProjectResponseMapper? _instance;
  static GetProjectResponseMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GetProjectResponseMapper._());
      APIResponseMapper.ensureInitialized();
      ProjectMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'GetProjectResponse';

  static Project _$project(GetProjectResponse v) => v.project;
  static const Field<GetProjectResponse, Project> _f$project =
      Field('project', _$project);

  @override
  final MappableFields<GetProjectResponse> fields = const {
    #project: _f$project,
  };

  static GetProjectResponse _instantiate(DecodingData data) {
    return GetProjectResponse(project: data.dec(_f$project));
  }

  @override
  final Function instantiate = _instantiate;

  static GetProjectResponse fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GetProjectResponse>(map);
  }

  static GetProjectResponse fromJson(String json) {
    return ensureInitialized().decodeJson<GetProjectResponse>(json);
  }
}

mixin GetProjectResponseMappable {
  String toJson() {
    return GetProjectResponseMapper.ensureInitialized()
        .encodeJson<GetProjectResponse>(this as GetProjectResponse);
  }

  Map<String, dynamic> toMap() {
    return GetProjectResponseMapper.ensureInitialized()
        .encodeMap<GetProjectResponse>(this as GetProjectResponse);
  }

  GetProjectResponseCopyWith<GetProjectResponse, GetProjectResponse,
          GetProjectResponse>
      get copyWith => _GetProjectResponseCopyWithImpl<GetProjectResponse,
          GetProjectResponse>(this as GetProjectResponse, $identity, $identity);
  @override
  String toString() {
    return GetProjectResponseMapper.ensureInitialized()
        .stringifyValue(this as GetProjectResponse);
  }

  @override
  bool operator ==(Object other) {
    return GetProjectResponseMapper.ensureInitialized()
        .equalsValue(this as GetProjectResponse, other);
  }

  @override
  int get hashCode {
    return GetProjectResponseMapper.ensureInitialized()
        .hashValue(this as GetProjectResponse);
  }
}

extension GetProjectResponseValueCopy<$R, $Out>
    on ObjectCopyWith<$R, GetProjectResponse, $Out> {
  GetProjectResponseCopyWith<$R, GetProjectResponse, $Out>
      get $asGetProjectResponse => $base.as(
          (v, t, t2) => _GetProjectResponseCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class GetProjectResponseCopyWith<$R, $In extends GetProjectResponse,
    $Out> implements ClassCopyWith<$R, $In, $Out> {
  ProjectCopyWith<$R, Project, Project> get project;
  $R call({Project? project});
  GetProjectResponseCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
      Then<$Out2, $R2> t);
}

class _GetProjectResponseCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, GetProjectResponse, $Out>
    implements GetProjectResponseCopyWith<$R, GetProjectResponse, $Out> {
  _GetProjectResponseCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<GetProjectResponse> $mapper =
      GetProjectResponseMapper.ensureInitialized();
  @override
  ProjectCopyWith<$R, Project, Project> get project =>
      $value.project.copyWith.$chain((v) => call(project: v));
  @override
  $R call({Project? project}) =>
      $apply(FieldCopyWithData({if (project != null) #project: project}));
  @override
  GetProjectResponse $make(CopyWithData data) =>
      GetProjectResponse(project: data.get(#project, or: $value.project));

  @override
  GetProjectResponseCopyWith<$R2, GetProjectResponse, $Out2> $chain<$R2, $Out2>(
          Then<$Out2, $R2> t) =>
      _GetProjectResponseCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class GetContextResponseMapper extends ClassMapperBase<GetContextResponse> {
  GetContextResponseMapper._();

  static GetContextResponseMapper? _instance;
  static GetContextResponseMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GetContextResponseMapper._());
      APIResponseMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'GetContextResponse';

  static Map<String, Object?> _$context(GetContextResponse v) => v.context;
  static const Field<GetContextResponse, Map<String, Object?>> _f$context =
      Field('context', _$context);

  @override
  final MappableFields<GetContextResponse> fields = const {
    #context: _f$context,
  };

  static GetContextResponse _instantiate(DecodingData data) {
    return GetContextResponse(context: data.dec(_f$context));
  }

  @override
  final Function instantiate = _instantiate;

  static GetContextResponse fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GetContextResponse>(map);
  }

  static GetContextResponse fromJson(String json) {
    return ensureInitialized().decodeJson<GetContextResponse>(json);
  }
}

mixin GetContextResponseMappable {
  String toJson() {
    return GetContextResponseMapper.ensureInitialized()
        .encodeJson<GetContextResponse>(this as GetContextResponse);
  }

  Map<String, dynamic> toMap() {
    return GetContextResponseMapper.ensureInitialized()
        .encodeMap<GetContextResponse>(this as GetContextResponse);
  }

  GetContextResponseCopyWith<GetContextResponse, GetContextResponse,
          GetContextResponse>
      get copyWith => _GetContextResponseCopyWithImpl<GetContextResponse,
          GetContextResponse>(this as GetContextResponse, $identity, $identity);
  @override
  String toString() {
    return GetContextResponseMapper.ensureInitialized()
        .stringifyValue(this as GetContextResponse);
  }

  @override
  bool operator ==(Object other) {
    return GetContextResponseMapper.ensureInitialized()
        .equalsValue(this as GetContextResponse, other);
  }

  @override
  int get hashCode {
    return GetContextResponseMapper.ensureInitialized()
        .hashValue(this as GetContextResponse);
  }
}

extension GetContextResponseValueCopy<$R, $Out>
    on ObjectCopyWith<$R, GetContextResponse, $Out> {
  GetContextResponseCopyWith<$R, GetContextResponse, $Out>
      get $asGetContextResponse => $base.as(
          (v, t, t2) => _GetContextResponseCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class GetContextResponseCopyWith<$R, $In extends GetContextResponse,
    $Out> implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>
      get context;
  $R call({Map<String, Object?>? context});
  GetContextResponseCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
      Then<$Out2, $R2> t);
}

class _GetContextResponseCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, GetContextResponse, $Out>
    implements GetContextResponseCopyWith<$R, GetContextResponse, $Out> {
  _GetContextResponseCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<GetContextResponse> $mapper =
      GetContextResponseMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>
      get context => MapCopyWith($value.context,
          (v, t) => ObjectCopyWith(v, $identity, t), (v) => call(context: v));
  @override
  $R call({Map<String, Object?>? context}) =>
      $apply(FieldCopyWithData({if (context != null) #context: context}));
  @override
  GetContextResponse $make(CopyWithData data) =>
      GetContextResponse(context: data.get(#context, or: $value.context));

  @override
  GetContextResponseCopyWith<$R2, GetContextResponse, $Out2> $chain<$R2, $Out2>(
          Then<$Out2, $R2> t) =>
      _GetContextResponseCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
