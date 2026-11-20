import 'dart:io';

import '../models/project_model.dart';
import '../utils/file_utils.dart';
import '../utils/constants.dart';
import 'workflow.dart';

/// Manages the .gitignore file for FVM projects.
///
/// Handles adding the necessary entries to ignore the FVM version cache directory
/// in git repositories. Provides interactive and non-interactive options to update
/// the .gitignore file.
class SetupGitIgnoreWorkflow extends Workflow {
  /// The path pattern to add to the .gitignore file.
  ///
  /// Uses the [kFvmDirName] constant from constants.dart to ensure consistency.
  static const String kFvmPathToAdd = '$kFvmDirName/';

  /// The heading to add before the FVM entries in the .gitignore file.
  ///
  /// This helps users understand why these entries are present.
  static const String kGitIgnoreHeading = '# FVM Version Cache';

  /// Creates a new [SetupGitIgnoreWorkflow] with the provided context.
  const SetupGitIgnoreWorkflow(super.context);

  /// Updates the project's .gitignore file to include FVM-specific entries.
  ///
  /// Adds [kFvmPathToAdd] to the project's .gitignore file if it doesn't already
  /// exist. Removes any older FVM-related entries before adding the new ones.
  ///
  /// If [updateGitIgnore] is disabled in the project config, this operation is skipped.
  ///
  /// Automatically applies the changes without prompting for improved user experience.
  ///
  /// Returns `true` if the operation was successful or if no action was needed,
  /// and `false` if an error occurred during file operations.
  bool call(Project project) {
    // Check if gitignore management is enabled for this project
    final updateGitIgnore = project.config?.updateGitIgnore ?? true;

    if (!updateGitIgnore) {
      return true;
    }

    final ignoreFile = project.gitIgnoreFile;

    checkManagedPath(project.path, ignoreFile.path);

    // Create the .gitignore file if it doesn't exist
    if (!ignoreFile.existsSync()) {
      try {
        ignoreFile.createSync(recursive: true);
      } catch (e) {
        logger.err('Failed to create .gitignore file: $e');

        return false;
      }
    }

    // Read the current content of the .gitignore file
    List<String> lines;
    try {
      lines = ignoreFile.readAsLinesSync();
    } catch (e) {
      logger.err('Failed to read .gitignore file: $e');

      return false;
    }

    // Check if the entry already exists
    if (lines.any((line) => line.trim() == kFvmPathToAdd)) {
      return true;
    }

    // Remove any existing FVM-related entries
    lines = lines
        .where(
          (line) =>
              !line.startsWith(kFvmDirName) && line.trim() != kGitIgnoreHeading,
        )
        .toList();

    // Append the correct line at the end
    lines.addAll(['', kGitIgnoreHeading, kFvmPathToAdd]);

    // Remove any consecutive blank lines to keep the file clean
    lines = lines.fold<List<String>>([], (previousValue, element) {
      if (previousValue.isEmpty) {
        previousValue.add(element);
      } else {
        final lastLine = previousValue.last;
        if (lastLine.trim().isEmpty && element.trim().isEmpty) {
          return previousValue;
        }
        previousValue.add(element);
      }

      return previousValue;
    });

    // Write the updated content to the .gitignore file silently
    try {
      ignoreFile.writeAsStringSync(lines.join('\n'), mode: FileMode.write);

      return true;
    } catch (e) {
      logger.err('Failed to update .gitignore file: $e');

      return false;
    }
  }
}
