import 'dart:async';

import 'package:path/path.dart' as p;

import '../models/cache_flutter_version_model.dart';
import '../models/project_model.dart';
import '../utils/file_utils.dart';
import '../services/project_service.dart';
import '../utils/exceptions.dart';
import '../utils/extensions.dart';
import 'check_project_constraints.workflow.dart';
import 'workflow.dart';

class UpdateProjectReferencesWorkflow extends Workflow {
  // Constants
  static const String versionFile = 'version';
  static const String releaseFile = 'release';
  static const String flutterSdkLink = 'flutter_sdk';

  const UpdateProjectReferencesWorkflow(super.context);

  void _withFsError(String message, void Function() action) {
    try {
      action();
    } on Exception catch (e) {
      logger.err(message);
      logger.debug('$e');
      rethrow;
    }
  }

  /// Updates the link to make sure it's always correct
  ///
  /// This method updates the .fvm symlink in the provided [project] to point to the cache
  /// directory of the currently pinned Flutter SDK version. It also cleans up legacy links
  /// that are no longer needed.
  void _updateLocalSdkReference(Project project, CacheFlutterVersion version) {
    checkManagedPath(project.path, project.localFvmPath);
    _withFsError('Failed to create local FVM path', () {
      // Only create the directory if it doesn't exist
      if (!project.localFvmPath.dir.existsSync()) {
        project.localFvmPath.dir.createSync(recursive: true);
      }
    });

    final sdkVersionFile = p.join(project.localFvmPath, versionFile);
    final sdkReleaseFile = p.join(project.localFvmPath, releaseFile);

    checkManagedPath(project.path, sdkVersionFile);
    checkManagedPath(project.path, sdkReleaseFile);
    _withFsError('Failed to write to version file', () {
      final flutterSdkVersion = version.flutterSdkVersion?.trim();
      final versionFileContents =
          (flutterSdkVersion == null || flutterSdkVersion.isEmpty)
              ? version.nameWithAlias
              : flutterSdkVersion;

      sdkVersionFile.file.write(versionFileContents);
    });

    _withFsError('Failed to write to release file', () {
      sdkReleaseFile.file.write(version.name);
    });

    if (!context.privilegedAccess) {
      logger.debug('Skipping symlink creation: no privileged access');

      return;
    }

    _withFsError('Failed to prepare versions cache directory', () {
      checkManagedPath(project.path, project.localVersionsCachePath);
      checkManagedPath(
          project.path, p.dirname(project.localVersionSymlinkPath));
      project.localVersionsCachePath.dir.createSync(recursive: true);

      if (version.fromFork) {
        final forkDir = p.join(project.localVersionsCachePath, version.fork!);
        if (!forkDir.dir.existsSync()) {
          forkDir.dir.createSync(recursive: true);
        }
      }
    });

    _withFsError('Failed to create version symlink', () {
      if (project.localVersionSymlinkPath.link.existsSync()) {
        project.localVersionSymlinkPath.link.deleteSync();
      }
      project.localVersionSymlinkPath.link.createLink(version.directory);
    });
  }

  /// Updates the `flutter_sdk` link to ensure it always points to the pinned SDK version.
  ///
  /// This is required for Android Studio to work with different Flutter SDK versions.
  ///
  /// Throws an [AppException] if the project doesn't have a pinned Flutter SDK version.
  void _updateCurrentSdkReference(
    Project project,
    CacheFlutterVersion version,
  ) {
    final currentSdkLink = p.join(project.localFvmPath, flutterSdkLink);

    if (currentSdkLink.link.existsSync()) {
      _withFsError('Failed to delete existing flutter_sdk symlink', () {
        currentSdkLink.link.deleteSync();
      });
    }

    if (!context.privilegedAccess) {
      logger.debug('Skipping symlink creation: no privileged access');

      return;
    }

    _withFsError('Failed to create flutter_sdk symlink', () {
      currentSdkLink.link.createLink(version.directory);
    });
  }

  /// Updates all SDK references in the project
  FutureOr<Project> call(
    Project project,
    CacheFlutterVersion version, {
    String? flavor,
    bool force = false,
  }) async {
    try {
      await get<CheckProjectConstraintsWorkflow>().call(
        project,
        version,
        force: force,
      );

      logger
        ..debug()
        ..debug('Updating project config')
        ..debug('Project name: ${project.name}')
        ..debug('Project path: ${project.path}')
        ..debug('Flutter version: ${version.nameWithAlias}')
        ..debug('');

      final updatedProject = get<ProjectService>().update(
        project,
        flavors: {if (flavor != null) flavor: version.nameWithAlias},
        flutterSdkVersion: version.nameWithAlias,
      );

      _updateLocalSdkReference(updatedProject, version);

      _updateCurrentSdkReference(updatedProject, version);

      return updatedProject;
    } on Exception catch (e, stackTrace) {
      Error.throwWithStackTrace(
        AppDetailedException('Error updating project references', e.toString()),
        stackTrace,
      );
    }
  }
}
