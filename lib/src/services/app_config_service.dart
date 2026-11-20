import 'dart:io';

import '../models/config_model.dart';
import '../utils/helpers.dart';

const String flutterGitUrl = 'FLUTTER_GIT_URL';

/// Service to manage FVM Config
class AppConfigService {
  const AppConfigService._();

  /// Build FVM Config
  static AppConfig buildConfig({AppConfig? overrides, String? appConfigPath}) {
    final globalConfig = LocalAppConfig.read(path: appConfigPath);
    final envConfig = _loadEnvironment();
    final projectConfig = _loadProjectConfig();

    final result = createAppConfig(
      globalConfig: globalConfig,
      envConfig: envConfig,
      projectConfig: projectConfig,
      overrides: overrides,
    );

    // Ensure forks are preserved from global config if result has none
    if (result.forks.isEmpty && globalConfig.forks.isNotEmpty) {
      return result.copyWith(forks: globalConfig.forks);
    }

    return result;
  }

  static AppConfig createAppConfig({
    required LocalAppConfig globalConfig,
    required Config? envConfig,
    required ProjectConfig? projectConfig,
    required AppConfig? overrides,
  }) {
    final validConfigs =
        [globalConfig, envConfig, projectConfig, overrides].whereType<Config>();

    var appConfig = AppConfig();

    for (final config in validConfigs) {
      if (config is AppConfig) {
        appConfig = appConfig.copyWith.$merge(config);
      }
      if (config is LocalAppConfig) {
        appConfig = appConfig.copyWith.$merge(
          AppConfig(
            cachePath: config.cachePath,
            useGitCache: config.useGitCache,
            gitCachePath: config.gitCachePath,
            flutterUrl: config.flutterUrl,
            privilegedAccess: config.privilegedAccess,
            runPubGetOnSdkChanges: config.runPubGetOnSdkChanges,
            updateVscodeSettings: config.updateVscodeSettings,
            updateGitIgnore: config.updateGitIgnore,
            disableUpdateCheck: config.disableUpdateCheck,
            lastUpdateCheck: config.lastUpdateCheck,
            forks: config.forks,
          ),
        );
      }

      // A checkout controls project preferences, but only the operator can
      // choose executable sources, shared storage, and privilege settings.
      if (config is ProjectConfig) {
        appConfig = appConfig.copyWith.$merge(
          AppConfig(
            runPubGetOnSdkChanges: config.runPubGetOnSdkChanges,
            updateVscodeSettings: config.updateVscodeSettings,
            updateGitIgnore: config.updateGitIgnore,
          ),
        );
      }

      if (config is EnvConfig) {
        appConfig = appConfig.copyWith.$merge(
          AppConfig(
            cachePath: config.cachePath,
            useGitCache: config.useGitCache,
            gitCachePath: config.gitCachePath,
            flutterUrl: config.flutterUrl,
          ),
        );
      }
    }

    return appConfig;
  }

  static ProjectConfig? _loadProjectConfig() {
    return lookUpDirectoryAncestor(
      directory: Directory.current,
      validate: ProjectConfig.loadFromDirectory,
    );
  }

  static Config _loadEnvironment() {
    final environments = Platform.environment;

    var config = EnvConfig();
    // Default to Flutter's environment variable if present; can still be overridden
    if (environments.containsKey(flutterGitUrl)) {
      config = config.copyWith(flutterUrl: environments[flutterGitUrl]);
    }

    // Apply each environment variable if it exists, with legacy fallback for cachePath
    for (final envVar in ConfigOptions.values) {
      final value = environments[envVar.envKey];

      if (envVar == ConfigOptions.cachePath) {
        // Legacy support: Use FVM_HOME as fallback if FVM_CACHE_PATH is not set
        final legacyFvmHome = environments['FVM_HOME'];
        config = config.copyWith(cachePath: value ?? legacyFvmHome);
      } else if (value != null) {
        switch (envVar) {
          case ConfigOptions.useGitCache:
            config = config.copyWith(useGitCache: stringToBool(value));
            break;
          case ConfigOptions.gitCachePath:
            config = config.copyWith(gitCachePath: value);
            break;
          case ConfigOptions.flutterUrl:
            config = config.copyWith(flutterUrl: value);
            break;
          case ConfigOptions.cachePath:
            // Already handled above
            break;
        }
      }
    }

    return config;
  }
}
