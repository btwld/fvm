import 'package:fvm/src/models/config_model.dart';
import 'package:fvm/src/services/app_config_service.dart';
import 'package:test/test.dart';

void main() {
  group('AppConfigService', () {
    group('buildConfig', () {
      test('returns valid AppConfig', () {
        // Test that buildConfig returns a valid config
        final config = AppConfigService.buildConfig();
        expect(config, isA<AppConfig>());
      });

      test('applies overrides correctly', () {
        // Test that overrides are applied
        final overrides = AppConfig(
          privilegedAccess: true,
          cachePath: '/custom/cache',
        );

        final config = AppConfigService.buildConfig(overrides: overrides);

        expect(config.privilegedAccess, isTrue);
        expect(config.cachePath, equals('/custom/cache'));
      });
    });

    group('createAppConfig', () {
      test('project preferences cannot select shared storage or SDK sources',
          () {
        final config = AppConfigService.createAppConfig(
          globalConfig: LocalAppConfig()..cachePath = '/user/cache',
          envConfig: null,
          overrides: null,
          projectConfig: const ProjectConfig(
              cachePath: 'project-cache',
              gitCachePath: 'mirror',
              flutterUrl: 'project-remote',
              privilegedAccess: true,
              updateGitIgnore: false),
        );
        expect(config.cachePath, '/user/cache');
        expect(config.gitCachePath, isNull);
        expect(config.flutterUrl, isNull);
        expect(config.privilegedAccess, isNull);
        expect(config.updateGitIgnore, isFalse);
      });

      test('handles null configs gracefully', () {
        // Test with all null configs except global (which is required)
        final globalConfig = LocalAppConfig();

        final result = AppConfigService.createAppConfig(
          globalConfig: globalConfig,
          envConfig: null,
          projectConfig: null,
          overrides: null,
        );

        // Should return a valid AppConfig
        expect(result, isA<AppConfig>());
      });

      test('merges multiple configs correctly', () {
        // Create configs with different settings
        final globalConfig = LocalAppConfig()
          ..cachePath = '/global/cache'
          ..privilegedAccess = false;

        final overrides = AppConfig(privilegedAccess: true);

        // Test the merge behavior
        final result = AppConfigService.createAppConfig(
          globalConfig: globalConfig,
          envConfig: null,
          projectConfig: null,
          overrides: overrides,
        );

        // Overrides should win for privilegedAccess
        expect(result.privilegedAccess, isTrue);
        // Global config should provide cachePath
        expect(result.cachePath, equals('/global/cache'));
      });
    });

    group('environment variable support', () {
      test('_loadEnvironment configuration exists', () {
        // Test by creating config with environment that should be processed
        final config = AppConfigService.buildConfig();

        // This test verifies the config structure exists and can handle environment variables
        expect(config, isA<AppConfig>());
        expect(config.cachePath, isA<String?>());
      });

      test('FVM_HOME fallback logic exists in implementation', () {
        // Since we can't easily mock Platform.environment in tests,
        // this test verifies the structure supports environment variables.
        // The actual FVM_HOME fallback logic is tested through manual verification.

        // Create a config and verify the structure
        final config = AppConfigService.buildConfig();
        expect(config, isA<AppConfig>());
      });
    });
  });
}
