import 'dart:io';

import '../models/config_model.dart';
import '../models/project_model.dart';
import '../utils/file_utils.dart';
import '../utils/extensions.dart';
import '../utils/helpers.dart';
import 'base_service.dart';

/// Flutter Project Services
/// APIs for interacting with local Flutter projects
///
/// This class provides methods for interacting with local Flutter projects.
class ProjectService extends ContextualService {
  const ProjectService(super.context);

  /// Recursive look up to find nested project directory
  /// Can start at a specific [directory] if provided
  ///
  /// This method performs a recursive search to find the nearest ancestor
  /// directory that contains a Flutter project. If a specific [directory] is provided,
  /// the search starts from that directory. Otherwise, the search starts from the
  /// current working directory.
  ///
  /// Returns the [Project] instance for the found project.
  Project findAncestor({Directory? directory}) {
    // Get directory, defined root or current
    directory ??= Directory(context.workingDirectory);

    final project = lookUpDirectoryAncestor(
      directory: directory,
      validate: (directory) {
        final project = Project.loadFromDirectory(directory);

        return project.hasConfig ? project : null;
      },
      debugPrinter: logger.debug,
    );

    final result =
        project ?? Project.loadFromDirectory(context.workingDirectory.dir);

    // Warn if config was loaded from legacy .fvm/fvm_config.json
    if (result.hasConfig && !File(result.configPath).existsSync()) {
      logger.warn(
        'Using legacy config at ${result.legacyConfigPath}. '
        'Consider migrating to .fvmrc by running: fvm use <version>',
      );
    }

    return result;
  }

  /// Finds the nearest project, returning null when its metadata cannot be
  /// read. Use this only for optional project-aware behavior.
  Project? tryFindAncestor({Directory? directory}) {
    try {
      return findAncestor(directory: directory);
    } catch (error, stackTrace) {
      logger.debug('Unable to read project metadata: $error');
      logger.logTrace(stackTrace);

      return null;
    }
  }

  /// Search for version configured
  ///
  /// This method searches for the version of the Flutter SDK that is configured for
  /// the current project. It uses the [findAncestor] method to find the project directory.
  ///
  /// Returns the pinned Flutter SDK version for the project, or `null` if no version is configured.
  /// The returned string includes the fork prefix if present (e.g., `fork/3.35.4`).
  String? findVersion() {
    final project = findAncestor();

    return project.pinnedVersion?.nameWithAlias;
  }

  /// Update the project with new configurations
  ///
  /// The [project] parameter is the project to be updated. The optional parameters are:
  /// - [flavors]: A map of flavor configurations.
  /// - [pinnedVersion]: The new pinned version of the Flutter SDK.
  ///
  /// This method updates the project's configuration with the provided parameters. It creates
  /// or updates the project's config file. The updated project is returned.
  Project update(
    Project project, {
    Map<String, String>? flavors,
    String? flutterSdkVersion,
    bool? updateVscodeSettings,
  }) {
    final currentConfig = project.config ?? ProjectConfig();

    // Merge flavors and set to null if empty
    final mergedFlavors = flavors != null
        ? {...?currentConfig.flavors, ...flavors}
        : currentConfig.flavors;

    final config = currentConfig.copyWith.$merge(
      ProjectConfig(
        flutter: flutterSdkVersion,
        flavors: mergedFlavors?.isNotEmpty == true ? mergedFlavors : null,
        updateVscodeSettings: updateVscodeSettings,
      ),
    );

    // Update flavors
    final projectConfig = project.configPath.file;
    final legacyConfigFile = project.legacyConfigPath.file;

    checkManagedPath(project.path, projectConfig.path);
    checkManagedPath(project.path, legacyConfigFile.path);

    // If config file does not exists create it
    if (!projectConfig.existsSync()) {
      projectConfig.createSync(recursive: true);
    }

    projectConfig.write(config.toJson());
    legacyConfigFile.write(config.toLegacyJson());

    return project.copyWith(config: config);
  }
}
