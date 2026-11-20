import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../models/project_model.dart';
import '../utils/file_utils.dart';
import '../utils/constants.dart';
import '../utils/convert_posix_path.dart';
import 'workflow.dart';

/// Manages Melos settings for monorepo projects using FVM.
///
/// Configures Melos settings (melos.yaml) to work with the FVM-managed Flutter SDK
/// by setting the sdkPath to point to the local .fvm/flutter_sdk symlink.
class UpdateMelosSettingsWorkflow extends Workflow {
  /// Creates a new [UpdateMelosSettingsWorkflow] with the provided context.
  const UpdateMelosSettingsWorkflow(super.context);

  /// Finds melos.yaml file in the project or parent directories.
  ///
  /// Searches up to the git root or filesystem root.
  File? _findMelosFile(Project project) {
    var currentDir = Directory(project.path);

    // Search up to git root or filesystem root
    while (true) {
      final melosFile = File(p.join(currentDir.path, 'melos.yaml'));

      if (melosFile.existsSync()) {
        logger.debug('Found melos.yaml at: ${melosFile.path}');

        return melosFile;
      }

      // Check if we've reached git root (handles both .git directory and .git file for worktrees)
      final gitDir = Directory(p.join(currentDir.path, '.git'));
      final gitFile = File(p.join(currentDir.path, '.git'));
      if (gitDir.existsSync() || gitFile.existsSync()) {
        logger.debug('Reached git root, no melos.yaml found');

        return null;
      }

      // Move to parent directory
      final parent = currentDir.parent;
      if (parent.path == currentDir.path) {
        // Reached filesystem root
        logger.debug('Reached filesystem root, no melos.yaml found');

        return null;
      }

      currentDir = parent;
    }
  }

  /// Calculates the relative path from melos.yaml to the Flutter SDK.
  String _calculateSdkPath(Project project, File melosFile) {
    final melosDir = p.dirname(melosFile.path);
    final flutterSdkPath = p.join(project.localFvmPath, 'flutter_sdk');
    final sdkPath = p.relative(flutterSdkPath, from: melosDir);

    // Always convert to POSIX format for YAML compatibility
    return convertToPosixPath(sdkPath);
  }

  /// Checks if the given path points to an FVM-managed Flutter SDK.
  bool _isFvmPath(String path) {
    return path.contains('.fvm/') || path.contains('.fvm\\');
  }

  /// Updates the melos.yaml file with the Flutter SDK path.
  void _updateMelosFile(Project project, File melosFile) {
    try {
      final contents = melosFile.readAsStringSync();
      final yamlEditor = YamlEditor(contents);

      // Parse to check current state
      final yaml = loadYaml(contents);
      final currentSdkPath = yaml is Map ? yaml['sdkPath'] : null;
      final expectedSdkPath = _calculateSdkPath(project, melosFile);

      if (currentSdkPath == null) {
        // Ask for confirmation before adding sdkPath
        logger.info('Detected melos.yaml without FVM configuration.');
        final confirm = logger.confirm(
          'Would you like to configure melos.yaml to use FVM-managed Flutter SDK?',
          defaultValue: false,
        );

        if (!confirm) {
          logger.debug('User declined to configure melos.yaml for FVM.');

          return;
        }

        // Add sdkPath
        yamlEditor.update(['sdkPath'], expectedSdkPath);
        melosFile.writeAsStringSync(yamlEditor.toString());
        logger.success('Added FVM Flutter SDK path to melos.yaml');
      } else if (_isFvmPath(currentSdkPath.toString())) {
        // Check if update needed
        if (currentSdkPath != expectedSdkPath) {
          // Ask for confirmation before updating existing FVM path
          final confirm = logger.confirm(
            'Update existing FVM path in melos.yaml from "$currentSdkPath" to "$expectedSdkPath"?',
            defaultValue: false,
          );

          if (!confirm) {
            logger.debug('User declined to update FVM path in melos.yaml.');

            return;
          }

          yamlEditor.update(['sdkPath'], expectedSdkPath);
          melosFile.writeAsStringSync(yamlEditor.toString());
          logger.info('Updated FVM Flutter SDK path in melos.yaml');
        } else {
          logger.debug(
            'Flutter SDK path in melos.yaml is already configured correctly',
          );
        }
      } else {
        // Non-FVM path - warn but don't modify
        logger.warn(
          'melos.yaml uses custom Flutter SDK at $currentSdkPath.\n'
          'To use FVM-managed Flutter, update melos.yaml with:\n'
          '  sdkPath: $expectedSdkPath',
        );
      }
    } on YamlException catch (e) {
      logger.err(
        'Error parsing melos.yaml: ${e.message}\n'
        'Please ensure your melos.yaml is valid YAML format.',
      );
    } catch (e) {
      logger.err('Failed to update melos.yaml: $e');
    }
  }

  /// Updates Melos configuration for the project.
  ///
  /// Configures the "sdkPath" setting to point to the FVM-managed
  /// Flutter SDK in melos.yaml if the file exists.
  ///
  /// If [updateMelosSettings] is disabled in the project config, this operation is skipped.
  ///
  /// Returns void, but logs success or error messages.
  FutureOr<void> call(Project project) {
    // Check if Melos settings management is enabled for this project
    final updateMelosSettings = project.config?.updateMelosSettings ?? true;

    if (!updateMelosSettings) {
      logger.debug(
        '$kPackageName does not manage Melos settings for this project.',
      );

      return null;
    }

    if (project.pinnedVersion == null) {
      logger.debug(
        'Skipping Melos settings update - no pinned Flutter version.',
      );

      return null;
    }

    // Find melos.yaml file
    final melosFile = _findMelosFile(project);

    if (melosFile == null) {
      logger.debug('No melos.yaml file found in project hierarchy.');

      return null;
    }

    // Update melos.yaml
    checkManagedPath(melosFile.parent.path, melosFile.path);
    _updateMelosFile(project, melosFile);
  }
}
