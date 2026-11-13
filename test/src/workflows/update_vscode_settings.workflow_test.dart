import 'dart:io';

import 'package:fvm/src/models/config_model.dart';
import 'package:fvm/src/models/project_model.dart';
import 'package:fvm/src/services/logger_service.dart';
import 'package:fvm/src/services/project_service.dart';
import 'package:fvm/src/utils/convert_posix_path.dart';
import 'package:fvm/src/workflows/update_vscode_settings.workflow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../testing_utils.dart';

void main() {
  group('UpdateVsCodeSettingsWorkflow', () {
    late TestCommandRunner runner;
    late TempDirectoryTracker tempDirs;

    setUp(() {
      runner = TestFactory.commandRunner();
      tempDirs = TempDirectoryTracker();
    });

    tearDown(() {
      tempDirs.cleanUp();
    });

    test(
      'should handle relative vs absolute paths based on privileged access',
      () async {
        final testDir = tempDirs.create();
        // Create test project
        createPubspecYaml(testDir);
        createProjectConfig(ProjectConfig(flutter: '3.10.0'), testDir);

        // Create .vscode directory
        final vscodeDir = Directory(p.join(testDir.path, '.vscode'));
        vscodeDir.createSync();

        final project = runner.context.get<ProjectService>().findAncestor(
              directory: testDir,
            );

        // Test with privileged access

        final privilegedWorkflow = UpdateVsCodeSettingsWorkflow(
          TestFactory.context(privilegedAccess: true),
        );

        await privilegedWorkflow(project);

        // Verify relative path is used with privileged access
        final settingsFile = File(p.join(vscodeDir.path, 'settings.json'));
        final privilegedContents = settingsFile.readAsStringSync();
        expect(
          privilegedContents,
          contains('"dart.flutterSdkPath": ".fvm/versions/3.10.0"'),
        );

        final nonPrivilegedWorkflow = UpdateVsCodeSettingsWorkflow(
          TestFactory.context(privilegedAccess: false),
        );

        await nonPrivilegedWorkflow(project);

        // Verify absolute path is used without privileged access
        // Note: Path should be converted to POSIX format for JSON compatibility
        final nonPrivilegedContents = settingsFile.readAsStringSync();
        final expectedPath = convertToPosixPath(
          project.localVersionSymlinkPath,
        );
        expect(
          nonPrivilegedContents,
          contains('"dart.flutterSdkPath": "$expectedPath"'),
        );
      },
    );

    test(
      'should create and update VS Code settings when force is true',
      () async {
        final testDir = tempDirs.create();
        // Create test project
        createPubspecYaml(testDir, name: 'test_project_2');
        createProjectConfig(ProjectConfig(flutter: '3.10.0'), testDir);

        // Create .vscode directory to simulate VS Code project
        final vscodeDir = Directory(p.join(testDir.path, '.vscode'));
        vscodeDir.createSync();

        final project = runner.context.get<ProjectService>().findAncestor(
              directory: testDir,
            );
        expect(project.name, equals('test_project_2'));

        final workflow = UpdateVsCodeSettingsWorkflow(runner.context);

        // Run workflow
        await workflow(project);

        // Verify settings.json was created and contains expected content
        final settingsFile = File(p.join(vscodeDir.path, 'settings.json'));
        expect(settingsFile.existsSync(), isTrue);

        final contents = settingsFile.readAsStringSync();
        expect(contents, contains('dart.flutterSdkPath'));
        expect(contents, contains('.fvm/versions/3.10.0'));
      },
    );

    test(
      'should not update VS Code settings when config disables it',
      () async {
        final testDir = tempDirs.create();
        // Create test project with config
        createPubspecYaml(testDir);
        createProjectConfig(
          ProjectConfig(updateVscodeSettings: false),
          testDir,
        );

        // Create .vscode directory
        final vscodeDir = Directory(p.join(testDir.path, '.vscode'));
        vscodeDir.createSync();

        final project = runner.context.get<ProjectService>().findAncestor(
              directory: testDir,
            );
        final workflow = UpdateVsCodeSettingsWorkflow(runner.context);

        // Run workflow
        await workflow(project);

        // Verify settings.json was not created
        final settingsFile = File(p.join(vscodeDir.path, 'settings.json'));
        expect(settingsFile.existsSync(), isFalse);
      },
    );

    test(
      'should not warn when config explicitly disables VS Code settings',
      () async {
        final testDir = tempDirs.create();
        createPubspecYaml(testDir);
        createProjectConfig(
          ProjectConfig(flutter: '3.10.0', updateVscodeSettings: false),
          testDir,
        );
        Directory(p.join(testDir.path, '.vscode')).createSync();

        final project = runner.context.get<ProjectService>().findAncestor(
              directory: testDir,
            );
        await UpdateVsCodeSettingsWorkflow(runner.context)(project);

        expect(
          runner.context.get<Logger>().outputs.any(
                (message) => message.contains('not managing'),
              ),
          isFalse,
        );
      },
    );

    test(
      'should skip when no VS Code files are detected and not running from VS Code',
      () async {
        final testDir = tempDirs.create();
        // Create test project without .vscode directory
        createPubspecYaml(testDir);
        createProjectConfig(ProjectConfig(), testDir);

        final project = runner.context.get<ProjectService>().findAncestor(
              directory: testDir,
            );

        // Create workflow with test context that doesn't simulate VS Code environment
        final workflow = UpdateVsCodeSettingsWorkflow(runner.context);

        // Run workflow
        await workflow(project);

        // Check if VS Code directory was created
        final vscodeDir = Directory(p.join(testDir.path, '.vscode'));
        final settingsFile = File(p.join(vscodeDir.path, 'settings.json'));

        // The behavior depends on whether isVsCode() returns true (running from VS Code)
        // When running tests from VS Code, settings will be created
        // When running from command line, they should not be created
        final isRunningFromVsCode =
            Platform.environment['TERM_PROGRAM'] == 'vscode';

        if (isRunningFromVsCode) {
          // If running from VS Code, settings should be created
          expect(settingsFile.existsSync(), isTrue);
        } else {
          // If not running from VS Code, settings should not be created
          expect(settingsFile.existsSync(), isFalse);
        }
      },
    );

    test('should update existing VS Code settings correctly', () async {
      final testDir = tempDirs.create();
      // Create test project
      createPubspecYaml(testDir);
      createProjectConfig(ProjectConfig(flutter: '2.2.0'), testDir);

      // Create .vscode directory with existing settings
      final vscodeDir = Directory(p.join(testDir.path, '.vscode'));
      vscodeDir.createSync();

      final settingsFile = File(p.join(vscodeDir.path, 'settings.json'));
      settingsFile.writeAsStringSync('''
{
  "editor.formatOnSave": true,
  "editor.fontSize": 14,
  "dart.flutterSdkPath": "/some/old/path"
}
''');

      final project = runner.context.get<ProjectService>().findAncestor(
            directory: testDir,
          );
      final workflow = UpdateVsCodeSettingsWorkflow(runner.context);

      // Run workflow
      await workflow(project);

      // Verify settings were updated correctly
      final contents = settingsFile.readAsStringSync();
      expect(contents, contains('"editor.formatOnSave": true'));
      expect(contents, contains('"editor.fontSize": 14'));
      expect(contents, contains('"dart.flutterSdkPath":'));
      expect(contents, contains('.fvm/versions/2.2.0'));
      expect(contents, isNot(contains('/some/old/path')));
    });

    test('should handle invalid JSON in settings file', () async {
      final testDir = tempDirs.create();
      // Create test project
      createPubspecYaml(testDir);
      createProjectConfig(ProjectConfig(), testDir);

      // Create .vscode directory with invalid settings
      final vscodeDir = Directory(p.join(testDir.path, '.vscode'));
      vscodeDir.createSync();

      final settingsFile = File(p.join(vscodeDir.path, 'settings.json'));
      settingsFile.writeAsStringSync('''
{
  "editor.formatOnSave": true,
  "editor.fontSize": 14,
  "dart.flutterSdkPath": "/some/old/path"
  this is invalid json
}
''');

      final project = runner.context.get<ProjectService>().findAncestor(
            directory: testDir,
          );
      final workflow = UpdateVsCodeSettingsWorkflow(runner.context);

      // Run workflow - should fail gracefully
      await workflow(project);

      // Verify settings file remains unchanged
      final contents = settingsFile.readAsStringSync();
      expect(contents, contains('this is invalid json'));
    });

    test('should handle file permission errors gracefully', () async {
      // Skip on Windows where file permissions are different
      if (Platform.isWindows) {
        return;
      }

      final testDir = tempDirs.create();
      // Create test project
      createPubspecYaml(testDir);
      createProjectConfig(ProjectConfig(), testDir);

      // Create .vscode directory with read-only settings
      final vscodeDir = Directory(p.join(testDir.path, '.vscode'));
      vscodeDir.createSync();

      final settingsFile = File(p.join(vscodeDir.path, 'settings.json'));
      settingsFile.writeAsStringSync('{"editor.formatOnSave": true}');

      // Make the file read-only
      await Process.run('chmod', ['444', settingsFile.path]);

      try {
        final project = runner.context.get<ProjectService>().findAncestor(
              directory: testDir,
            );
        final workflow = UpdateVsCodeSettingsWorkflow(runner.context);

        // Run workflow - should fail gracefully
        await workflow(project);

        // Content should remain unchanged
        final contents = settingsFile.readAsStringSync();
        expect(contents, equals('{"editor.formatOnSave": true}'));
      } finally {
        // Restore permissions for cleanup
        await Process.run('chmod', ['644', settingsFile.path]);
      }
    });

    test('should update workspace file when it exists', () async {
      final testDir = tempDirs.create();
      // Create test project
      createPubspecYaml(testDir);
      createProjectConfig(ProjectConfig(flutter: '3.9.0'), testDir);

      // Create a workspace file
      final workspaceFile = File(
        p.join(testDir.path, 'project.code-workspace'),
      );
      workspaceFile.writeAsStringSync('''
{
  "folders": [
    {
      "path": "."
    }
  ],
  "settings": {
    "editor.formatOnSave": true
  }
}
''');

      final project = runner.context.get<ProjectService>().findAncestor(
            directory: testDir,
          );
      final workflow = UpdateVsCodeSettingsWorkflow(runner.context);

      // Run workflow
      await workflow(project);

      // Verify workspace file was updated
      final contents = workspaceFile.readAsStringSync();
      expect(
        contents,
        contains('"dart.flutterSdkPath": ".fvm/versions/3.9.0"'),
      );
      expect(contents, contains('"editor.formatOnSave": true'));
    });

    test('should correctly handle fork version in VS Code settings', () async {
      final testDir = tempDirs.create();
      // Create test project with fork version
      const forkName = 'my-fork';
      const versionName = '3.10.0';
      createPubspecYaml(testDir, name: 'test_fork_project');
      createProjectConfig(
        ProjectConfig(flutter: '$forkName/$versionName'),
        testDir,
      );

      // Create .vscode directory
      final vscodeDir = Directory(p.join(testDir.path, '.vscode'));
      vscodeDir.createSync();

      final project = runner.context.get<ProjectService>().findAncestor(
            directory: testDir,
          );

      // Verify the project correctly parsed the fork version
      expect(project.pinnedVersion?.fromFork, isTrue);
      expect(project.pinnedVersion?.fork, equals(forkName));
      expect(project.pinnedVersion?.name, equals(versionName));
      expect(
        project.pinnedVersion?.nameWithAlias,
        equals('$forkName/$versionName'),
      );

      // Verify localVersionSymlinkPath includes fork subdirectory
      expect(
        project.localVersionSymlinkPath,
        equals(p.join(testDir.path, '.fvm', 'versions', forkName, versionName)),
      );

      final workflow = UpdateVsCodeSettingsWorkflow(runner.context);

      // Run workflow
      await workflow(project);

      // Verify settings.json contains the correct fork version path
      final settingsFile = File(p.join(vscodeDir.path, 'settings.json'));
      expect(settingsFile.existsSync(), isTrue);

      final contents = settingsFile.readAsStringSync();
      expect(contents, contains('dart.flutterSdkPath'));
      // The path should include the fork subdirectory: .fvm/versions/my-fork/3.10.0
      expect(contents, contains('.fvm/versions/$forkName/$versionName'));
    });

    test('should update workspace file with fork version path', () async {
      final testDir = tempDirs.create();
      // Create test project with fork version
      const forkName = 'custom-fork';
      const versionName = '3.9.0';
      createPubspecYaml(testDir);
      createProjectConfig(
        ProjectConfig(flutter: '$forkName/$versionName'),
        testDir,
      );

      // Create a workspace file
      final workspaceFile = File(
        p.join(testDir.path, 'project.code-workspace'),
      );
      workspaceFile.writeAsStringSync('''
{
  "folders": [
    {
      "path": "."
    }
  ],
  "settings": {
    "editor.formatOnSave": true
  }
}
''');

      final project = runner.context.get<ProjectService>().findAncestor(
            directory: testDir,
          );
      final workflow = UpdateVsCodeSettingsWorkflow(runner.context);

      // Run workflow
      await workflow(project);

      // Verify workspace file was updated with fork version path
      final contents = workspaceFile.readAsStringSync();
      expect(
        contents,
        contains(
          '"dart.flutterSdkPath": ".fvm/versions/$forkName/$versionName"',
        ),
      );
      expect(contents, contains('"editor.formatOnSave": true'));
    });

    test('should handle non-existent parent directories correctly', () async {
      final testDir = tempDirs.create();
      // Create test project
      createPubspecYaml(testDir);
      createProjectConfig(ProjectConfig(), testDir);

      // Create a nested directory structure that doesn't exist yet
      final nestedDir = Directory(
        p.join(testDir.path, 'deeply', 'nested', 'dir'),
      );

      // Create .vscode directory in the nested path
      final vscodeDir = Directory(p.join(nestedDir.path, '.vscode'));
      vscodeDir.createSync(recursive: true);

      // Mock a project with this nested path
      final mockProject = Project(
        config: ProjectConfig(),
        path: nestedDir.path,
        pubspec: null,
      );

      final workflow = UpdateVsCodeSettingsWorkflow(runner.context);

      // Run workflow
      await workflow(mockProject);

      // Verify settings.json was created
      final settingsFile = File(p.join(vscodeDir.path, 'settings.json'));
      expect(settingsFile.existsSync(), isTrue);
    });
  });
}
