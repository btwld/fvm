import 'dart:async';
import 'dart:io';

import 'package:jsonc/jsonc.dart';
import 'package:path/path.dart' as p;

import '../models/project_model.dart';
import '../utils/constants.dart';
import '../utils/convert_posix_path.dart';
import '../utils/helpers.dart';
import '../utils/pretty_json.dart';
import 'workflow.dart';

/// Manages VS Code settings for Flutter projects using FVM.
///
/// Configures VS Code settings in both folder settings (.vscode/settings.json)
/// and workspace settings (.code-workspace) to work with the FVM-managed Flutter SDK.
class UpdateVsCodeSettingsWorkflow extends Workflow {
  /// The typical extension for VS Code workspace files
  static const String kWorkspaceFileExt = '.code-workspace';

  /// Creates a new [UpdateVsCodeSettingsWorkflow] with the provided context.
  const UpdateVsCodeSettingsWorkflow(super.context);

  /// Checks if the project has VS Code configuration files.
  bool _hasVsCodeFiles(Project project) {
    final vscodeDir = Directory(p.join(project.path, '.vscode'));

    return vscodeDir.existsSync();
  }

  /// Gets the relative path from the working directory for display purposes.
  String _getRelativePath(String filePath) {
    return p.relative(filePath, from: context.workingDirectory);
  }

  /// Handles JSON parsing errors with consistent error messaging.
  void _handleJsonParseError(
    String filePath,
    FormatException e,
    String fileType,
  ) {
    final relativePath = _getRelativePath(filePath);
    logger.err(
      'Error parsing $fileType at $relativePath: ${e.message}\n'
      'Please use a tool like https://jsonlint.com to validate and fix it',
    );
  }

  /// Validates that the Flutter SDK path exists and warns if not.
  void _validateSdkPath(Project project, String context) {
    if (project.pinnedVersion != null &&
        !Directory(project.localVersionSymlinkPath).existsSync()) {
      logger.warn(
        'Flutter SDK not found at ${project.localVersionSymlinkPath}, but updating $context anyway.',
      );
    }
  }

  /// Resolves the Flutter SDK path for VSCode settings.
  /// Returns relative path if privileged access, absolute path otherwise.
  /// Always converts to POSIX format for JSON compatibility on Windows.
  String _resolveSdkPath(Project project, {String? relativeTo}) {
    String sdkPath;

    if (context.privilegedAccess) {
      sdkPath = p.relative(
        project.localVersionSymlinkPath,
        from: relativeTo ?? project.path,
      );
    } else {
      sdkPath = project.localVersionSymlinkPath;
    }

    // Always convert to POSIX format for JSON compatibility
    // This prevents double-escaping of Windows backslashes in JSON output
    return convertToPosixPath(sdkPath);
  }

  /// Finds a VS Code workspace file in the project directory.
  ///
  /// Returns the most relevant workspace file or null if none is found.
  /// Prioritizes files containing the project name if available.
  File? _findWorkspaceFile(Project project) {
    try {
      final dirContents = Directory(project.path).listSync();
      final workspaceFiles = <File>[];

      // Collect all workspace files
      for (final entity in dirContents) {
        if (entity is File && entity.path.endsWith(kWorkspaceFileExt)) {
          workspaceFiles.add(entity);
        }
      }

      if (workspaceFiles.isEmpty) {
        return null;
      }

      // Log all found workspace files
      if (workspaceFiles.length > 1) {
        logger.debug('Found ${workspaceFiles.length} workspace files');
      } else {
        logger.debug(
          'Found workspace file: ${p.basename(workspaceFiles.first.path)}',
        );
      }

      // Prefer workspace files that might be related to the project
      final projectName = p.basename(project.path).toLowerCase();
      for (final file in workspaceFiles) {
        final fileName = p.basenameWithoutExtension(file.path).toLowerCase();
        if (fileName.contains(projectName) || projectName.contains(fileName)) {
          logger.debug('Selected workspace file: ${p.basename(file.path)}');

          return file;
        }
      }

      // Fall back to the first workspace file
      return workspaceFiles.first;
    } catch (e) {
      logger.debug('Error searching for workspace file: $e');

      return null;
    }
  }

  /// Updates the folder-level settings in .vscode/settings.json
  void _updateFolderSettings(Project project) {
    // Set up paths for VS Code settings
    final vscodeDir = Directory(p.join(project.path, '.vscode'));
    final vscodeSettingsFile = File(p.join(vscodeDir.path, 'settings.json'));

    // Check if project is using VS Code
    if (!isVsCode() && !_hasVsCodeFiles(project)) {
      logger.debug(
        'Project is not using $kVsCode, skipping folder settings update.',
      );

      return;
    }

    // Validate SDK path
    _validateSdkPath(project, 'VSCode settings');

    // Create the settings file if it doesn't exist
    if (!vscodeSettingsFile.existsSync()) {
      logger.debug('$kVsCode settings not found, creating new settings file.');
      try {
        vscodeSettingsFile.createSync(recursive: true);
      } catch (e) {
        logger.err('Failed to create $kVsCode settings file: $e');

        return;
      }
    }

    // Read current settings
    Map<String, dynamic> currentSettings = {};
    try {
      String contents = vscodeSettingsFile.readAsStringSync();
      if (contents.isNotEmpty) {
        currentSettings = jsonc.decode(contents);
      }
    } on FormatException catch (e) {
      _handleJsonParseError(vscodeSettingsFile.path, e, '$kVsCode settings');

      return;
    } catch (e) {
      final relativePath = _getRelativePath(vscodeSettingsFile.path);
      logger.err('Failed to read $kVsCode settings at $relativePath: $e');

      return;
    }

    // Update Flutter SDK path setting only if there's a pinned version
    try {
      if (project.pinnedVersion != null) {
        currentSettings["dart.flutterSdkPath"] = _resolveSdkPath(project);
        logger.success('Updated $kVsCode folder Flutter SDK path setting.');
      } else {
        logger.debug(
          'Skipping dart.flutterSdkPath setting - no pinned Flutter version.',
        );
      }

      // Write updated settings back to file
      vscodeSettingsFile.writeAsStringSync(prettyJson(currentSettings));
    } catch (e) {
      logger.err('Failed to update $kVsCode folder settings: $e');
    }
  }

  /// Updates all found workspace files with the correct Flutter SDK path
  void _updateWorkspaceFiles(Project project) {
    final workspaceFile = _findWorkspaceFile(project);

    if (workspaceFile == null) {
      logger.debug('No $kVsCode workspace files found.');

      return;
    }

    // Validate SDK path
    _validateSdkPath(project, 'workspace file');

    try {
      // Read workspace file
      String contents = workspaceFile.readAsStringSync();
      Map<String, dynamic> workspaceSettings = {};

      if (contents.isNotEmpty) {
        try {
          workspaceSettings = jsonc.decode(contents);
        } on FormatException catch (e) {
          _handleJsonParseError(workspaceFile.path, e, 'workspace file');

          return;
        }
      }

      // Initialize settings section if it doesn't exist
      workspaceSettings['settings'] ??= <String, dynamic>{};

      // Update Flutter SDK setting only if there's a pinned version
      if (project.pinnedVersion != null) {
        final workspaceDir = p.dirname(workspaceFile.path);
        final sdkPath = _resolveSdkPath(project, relativeTo: workspaceDir);
        workspaceSettings['settings']['dart.flutterSdkPath'] = sdkPath;
      } else {
        logger.debug(
          'Skipping dart.flutterSdkPath setting in workspace file - no pinned Flutter version.',
        );
      }

      // Write changes back
      workspaceFile.writeAsStringSync(prettyJson(workspaceSettings));

      final relativePath = _getRelativePath(workspaceFile.path);
      final message = project.pinnedVersion != null
          ? 'Updated Flutter SDK path in workspace file: $relativePath'
          : 'Updated workspace file: $relativePath';
      logger.success(message);
    } catch (e) {
      final relativePath = _getRelativePath(workspaceFile.path);
      logger.err('Failed to update workspace file $relativePath: $e');
      // Continue to next workspace file
    }
  }

  /// Updates VS Code configuration for the project.
  ///
  /// Configures the "dart.flutterSdkPath" setting to point to the FVM-managed
  /// Flutter SDK in both folder settings and workspace settings if applicable.
  ///
  /// If [updateVscodeSettings] is disabled in the project config, this operation is skipped.
  ///
  /// Returns void, but logs success or error messages.
  FutureOr<void> call(Project project) {
    // Check if VS Code settings management is enabled for this project
    final updateVscodeSettings = project.config?.updateVscodeSettings ?? true;

    if (project.pinnedVersion == null) {
      logger.warn(
        '$kPackageName: Project is not using a pinned Flutter version.',
      );
      // Continue execution but skip setting dart.flutterSdkPath
    }

    // An explicit opt-out is intentional configuration, so skip silently.
    if (!updateVscodeSettings) {
      logger.debug(
        '$kPackageName does not manage $kVsCode settings for this project '
        '("updateVscodeSettings": false in $kFvmConfigFileName).',
      );

      return null;
    }

    // Update project folder settings
    _updateFolderSettings(project);

    // Find and update workspace files if they exist
    _updateWorkspaceFiles(project);

    return null;
  }
}
