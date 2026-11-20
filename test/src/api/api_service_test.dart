import 'dart:io';

import 'package:fvm/fvm.dart';
import 'package:fvm/src/api/api_service.dart';
import 'package:fvm/src/api/models/json_response.dart';
import 'package:fvm/src/services/flutter_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../mocks.dart';
import '../../testing_utils.dart';

void main() {
  late FvmContext context;

  setUpAll(() {
    // Register any custom fallbacks for mocktail
    registerFallbackValue(MockFvmDirectory());
  });

  setUp(() {
    // Initialize all mocks

    context = TestFactory.fastContext(
      generators: {ProjectService: (_) => MockProjectService()},
    );
  });

  group('getContext', () {
    test('returns context wrapped in response object', () {
      // Execute
      final result = context.get<ApiService>().getContext();

      // Verify
      expect(result, isA<GetContextResponse>());
      expect(result.context, containsPair('fvmVersion', context.fvmVersion));
      expect(result.context, isNot(contains('environment')));
      expect(result.context, isNot(contains('args')));
      expect(result.context, isNot(contains('config')));
    });
  });

  group('getProject', () {
    test('returns project for null directory', () {
      // Set up
      final mockProject = MockProject();
      when(
        () => context.get<ProjectService>().findAncestor(directory: null),
      ).thenReturn(mockProject);

      // Execute
      final result = context.get<ApiService>().getProject();

      // Verify
      expect(result, isA<GetProjectResponse>());
      expect(result.project, equals(mockProject));
      verify(
        () => context.get<ProjectService>().findAncestor(directory: null),
      ).called(1);
    });

    test('returns project for specified directory', () {
      // Set up
      final directory = Directory('/test/path');
      final mockProject = MockProject();
      when(
        () => context.get<ProjectService>().findAncestor(directory: directory),
      ).thenReturn(mockProject);

      // Execute
      final result = context.get<ApiService>().getProject(directory);

      // Verify
      expect(result, isA<GetProjectResponse>());
      expect(result.project, equals(mockProject));
      verify(
        () => context.get<ProjectService>().findAncestor(directory: directory),
      ).called(1);
    });
  });

  group('getCachedVersions', () {
    setUp(() {
      // Usage reporting folds in the current project, so the mock has to
      // answer the ancestor lookup. An unconfigured project contributes none.
      when(
        () => context.get<ProjectService>().findAncestor(directory: null),
      ).thenReturn(
        Project(config: null, path: createTempDir('api').path, pubspec: null),
      );
    });

    test('returns versions with directories', () async {
      await context.get<FlutterService>().install(FlutterVersion.parse('beta'));

      await context.get<FlutterService>().install(
            FlutterVersion.parse('stable'),
          );

      final stableDir = context.get<CacheService>().getVersionCacheDir(
            FlutterVersion.parse('stable'),
          );
      final flutter3Dir = context.get<CacheService>().getVersionCacheDir(
            FlutterVersion.parse('beta'),
          );

      // Verify directories exist instead of checking sizes
      expect(
        stableDir.existsSync(),
        isTrue,
        reason: 'Stable directory should exist',
      );
      expect(
        flutter3Dir.existsSync(),
        isTrue,
        reason: 'Beta directory should exist',
      );

      final cachedVersionsResponse =
          await context.get<CacheService>().getAllVersions();

      // Execute
      final result = await context.get<ApiService>().getCachedVersions();

      // Verify
      expect(result, isA<GetCacheVersionsResponse>());
      expect(result.versions, equals(cachedVersionsResponse));
      // Only check that the size format is correct, not the exact value
      expect(result.size, matches(RegExp(r'^\d+(\.\d+)? [KMGT]?B$')));
    });

    test(
      'returns versions without size calculation when skipCacheSizeCalculation is true',
      () async {
        await context.get<FlutterService>().install(
              FlutterVersion.parse('3.0.0'),
            );

        await context.get<FlutterService>().install(
              FlutterVersion.parse('stable'),
            );

        final cachedVersionsResponse =
            await context.get<CacheService>().getAllVersions();

        // Execute
        final result = await context.get<ApiService>().getCachedVersions(
              skipCacheSizeCalculation: true,
            );

        // Verify
        expect(result, isA<GetCacheVersionsResponse>());
        expect(result.versions, equals(cachedVersionsResponse));
        expect(result.size, equals(formatFriendlyBytes(0)));
      },
    );
  });

  group('getReleases', () {
    late FlutterReleasesResponse releasesResponse;

    setUp(() async {
      releasesResponse =
          await context.get<FlutterReleaseClient>().fetchReleases();
    });

    test('returns all releases when no filters applied', () async {
      // Execute
      final result = await context.get<ApiService>().getReleases();

      // Verify
      expect(result, isA<GetReleasesResponse>());
      expect(result.versions, equals(releasesResponse.versions));
      expect(result.channels, equals(releasesResponse.channels));
    });

    test('returns limited releases when limit is specified', () async {
      // Execute
      final result = await context.get<ApiService>().getReleases(limit: 2);

      // Verify
      expect(result, isA<GetReleasesResponse>());
      expect(result.versions.length, equals(2));
      expect(result.channels, equals(releasesResponse.channels));
    });

    test('returns filtered releases when channel is specified', () async {
      // Execute
      final result = await context.get<ApiService>().getReleases(
            channelName: 'stable',
          );

      // Verify
      expect(result, isA<GetReleasesResponse>());
      expect(result.versions.every((v) => v.channel.name == 'stable'), isTrue);
      expect(result.channels, equals(releasesResponse.channels));
    });

    test(
      'returns limited and filtered releases when both limit and channel specified',
      () async {
        // Execute
        final result = await context.get<ApiService>().getReleases(
              limit: 1,
              channelName: 'stable',
            );

        // Verify
        expect(result, isA<GetReleasesResponse>());
        expect(result.versions.length, equals(1));
        expect(result.versions.first.channel.name, equals('stable'));
        expect(result.channels, equals(releasesResponse.channels));
      },
    );
  });
}
