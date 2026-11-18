import 'dart:io';

import 'package:fvm/src/models/cache_flutter_version_model.dart';
import 'package:fvm/src/models/config_model.dart';
import 'package:fvm/src/models/flutter_version_model.dart';
import 'package:fvm/src/models/project_model.dart';
import 'package:fvm/src/services/project_service.dart';
import 'package:fvm/src/utils/exceptions.dart';
import 'package:fvm/src/workflows/update_project_references.workflow.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../testing_utils.dart';

void main() {
  group('UpdateProjectReferencesWorkflow', () {
    late TestCommandRunner runner;
    late Directory cacheDir;
    late TempDirectoryTracker tempDirs;

    setUp(() {
      runner = TestFactory.commandRunner();
      tempDirs = TempDirectoryTracker();
      cacheDir = tempDirs.create();
    });

    tearDown(() {
      tempDirs.cleanUp();
    });

    // Helper function to create a properly structured cache version
    CacheFlutterVersion createCacheVersion(String version) {
      final versionDir = Directory(p.join(cacheDir.path, 'versions', version));
      versionDir.createSync(recursive: true);

      // Create bin directory
      final binDir = Directory(p.join(versionDir.path, 'bin'));
      binDir.createSync(recursive: true);

      // Create dart-sdk cache directory
      final dartSdkDir = Directory(p.join(binDir.path, 'cache', 'dart-sdk'));
      dartSdkDir.createSync(recursive: true);

      // Create version files
      File(p.join(versionDir.path, 'version')).writeAsStringSync(version);
      File(p.join(dartSdkDir.path, 'version')).writeAsStringSync('2.19.0');

      // Create a base FlutterVersion
      final flutterVersion = FlutterVersion.parse(version);

      // Return a CacheFlutterVersion with proper structure
      return CacheFlutterVersion.fromVersion(
        flutterVersion,
        directory: versionDir.path,
      );
    }

    test('refuses linked project metadata before writing its target', () async {
      final dir = tempDirs.create();
      final other = tempDirs.create();
      createPubspecYaml(dir);
      createProjectConfig(ProjectConfig(), dir);
      Link(p.join(dir.path, '.fvm')).createSync(other.path);
      final project =
          runner.context.get<ProjectService>().findAncestor(directory: dir);
      await expectLater(
          UpdateProjectReferencesWorkflow(runner.context)(
              project, createCacheVersion('3.10.0'),
              force: true),
          throwsA(isA<AppDetailedException>()));
      expect(other.listSync(), isEmpty);
    }, skip: Platform.isWindows);

    test('should successfully update project references', () async {
      final testDir = tempDirs.create();
      // Create test project
      createPubspecYaml(testDir, name: 'test_project');
      createProjectConfig(ProjectConfig(), testDir);

      final project = runner.context.get<ProjectService>().findAncestor(
            directory: testDir,
          );
      expect(project.name, equals('test_project'));

      // Create cache version
      final cacheVersion = createCacheVersion('3.10.0');

      final workflow = UpdateProjectReferencesWorkflow(runner.context);

      // Run workflow
      final updatedProject = await workflow.call(
        project,
        cacheVersion,
        force: true,
      );

      // Verify files were created
      final versionFile = File(
        p.join(
          testDir.path,
          '.fvm',
          UpdateProjectReferencesWorkflow.versionFile,
        ),
      );
      expect(versionFile.existsSync(), isTrue);
      expect(
        versionFile.readAsStringSync(),
        equals(cacheVersion.flutterSdkVersion),
      );

      final releaseFile = File(
        p.join(
          testDir.path,
          '.fvm',
          UpdateProjectReferencesWorkflow.releaseFile,
        ),
      );
      expect(releaseFile.existsSync(), isTrue);
      expect(releaseFile.readAsStringSync(), equals(cacheVersion.name));

      // Verify the project was updated with the correct version
      expect(updatedProject.pinnedVersion, cacheVersion.toFlutterVersion());
    });

    test(
      'should fall back to nameWithAlias when flutter SDK version is absent',
      () async {
        final testDir = tempDirs.create();
        createPubspecYaml(testDir, name: 'test_project');
        createProjectConfig(ProjectConfig(), testDir);

        final project = runner.context.get<ProjectService>().findAncestor(
              directory: testDir,
            );

        final versionDir = Directory(
          p.join(cacheDir.path, 'versions', 'stable'),
        );
        versionDir.createSync(recursive: true);

        // No flutter.version.json or version file to ensure flutterSdkVersion is null.
        final cacheVersion = CacheFlutterVersion.fromVersion(
          FlutterVersion.parse('stable'),
          directory: versionDir.path,
        );

        final workflow = UpdateProjectReferencesWorkflow(runner.context);

        await workflow.call(project, cacheVersion, force: true);

        final versionFile = File(
          p.join(
            testDir.path,
            '.fvm',
            UpdateProjectReferencesWorkflow.versionFile,
          ),
        );

        expect(versionFile.existsSync(), isTrue);
        expect(
          versionFile.readAsStringSync(),
          equals(cacheVersion.nameWithAlias),
        );
      },
    );

    test(
      'should fall back to nameWithAlias when flutter SDK version is empty string',
      () async {
        final testDir = tempDirs.create();
        createPubspecYaml(testDir, name: 'test_project');
        createProjectConfig(ProjectConfig(), testDir);

        final project = runner.context.get<ProjectService>().findAncestor(
              directory: testDir,
            );

        final versionDir = Directory(
          p.join(cacheDir.path, 'versions', '3.10.0'),
        );
        versionDir.createSync(recursive: true);

        // Create an empty version file (whitespace only) to test empty string fallback
        File(p.join(versionDir.path, 'version')).writeAsStringSync('   ');

        final cacheVersion = CacheFlutterVersion.fromVersion(
          FlutterVersion.parse('3.10.0'),
          directory: versionDir.path,
        );

        final workflow = UpdateProjectReferencesWorkflow(runner.context);

        await workflow.call(project, cacheVersion, force: true);

        final versionFile = File(
          p.join(
            testDir.path,
            '.fvm',
            UpdateProjectReferencesWorkflow.versionFile,
          ),
        );

        // Should fall back to nameWithAlias when version is empty/whitespace
        expect(versionFile.existsSync(), isTrue);
        expect(
          versionFile.readAsStringSync(),
          equals(cacheVersion.nameWithAlias),
        );
      },
    );

    test(
      'should fall back to nameWithAlias for fork version when SDK version is absent',
      () async {
        final testDir = tempDirs.create();
        createPubspecYaml(testDir, name: 'test_project');
        createProjectConfig(ProjectConfig(), testDir);

        final project = runner.context.get<ProjectService>().findAncestor(
              directory: testDir,
            );

        // Create a fork version directory without version files
        const forkName = 'my-fork';
        const versionName = 'stable';
        final forkVersionDir = Directory(
          p.join(cacheDir.path, 'versions', forkName, versionName),
        );
        forkVersionDir.createSync(recursive: true);

        // No version files to ensure flutterSdkVersion is null
        final flutterVersion = FlutterVersion.parse('$forkName/$versionName');
        final cacheVersion = CacheFlutterVersion.fromVersion(
          flutterVersion,
          directory: forkVersionDir.path,
        );

        final workflow = UpdateProjectReferencesWorkflow(runner.context);

        await workflow.call(project, cacheVersion, force: true);

        final versionFile = File(
          p.join(
            testDir.path,
            '.fvm',
            UpdateProjectReferencesWorkflow.versionFile,
          ),
        );

        // Should contain full fork/version string (nameWithAlias)
        expect(versionFile.existsSync(), isTrue);

        final versionFileContents = versionFile.readAsStringSync();
        expect(versionFileContents, equals('$forkName/$versionName'));
        expect(cacheVersion.nameWithAlias, equals('$forkName/$versionName'));
      },
    );

    test('should update with flavor when provided', () async {
      final testDir = tempDirs.create();
      createPubspecYaml(testDir);
      createProjectConfig(ProjectConfig(), testDir);

      final project = runner.context.get<ProjectService>().findAncestor(
            directory: testDir,
          );
      final cacheVersion = createCacheVersion('3.10.0');

      final workflow = UpdateProjectReferencesWorkflow(runner.context);

      // Run workflow with flavor
      final updatedProject = await workflow.call(
        project,
        cacheVersion,
        flavor: 'dev',
        force: true,
      );

      // Verify flavor was added (uses nameWithAlias for fork support)
      final flavor = updatedProject.flavors['dev'];
      expect(flavor, equals(cacheVersion.nameWithAlias));
    });

    test(
      'should create symlinks when privileged access is available',
      () async {
        // Skip on Windows where symlinks require admin rights
        if (Platform.isWindows) {
          return;
        }

        final testDir = tempDirs.create();
        createPubspecYaml(testDir);
        createProjectConfig(ProjectConfig(), testDir);

        final project = runner.context.get<ProjectService>().findAncestor(
              directory: testDir,
            );
        final cacheVersion = createCacheVersion('3.10.0');

        // Ensure context has privilegedAccess set to true
        final privilegedContext = TestFactory.context(privilegedAccess: true);

        final workflow = UpdateProjectReferencesWorkflow(privilegedContext);

        // Run workflow
        await workflow.call(project, cacheVersion, force: true);

        // Verify symlinks were created
        final flutterSdkLink = Link(
          p.join(
            testDir.path,
            '.fvm',
            UpdateProjectReferencesWorkflow.flutterSdkLink,
          ),
        );

        expect(flutterSdkLink.existsSync(), isTrue);
        expect(flutterSdkLink.targetSync(), equals(cacheVersion.directory));
      },
    );

    test(
      'should not create symlinks when privileged access is unavailable',
      () async {
        final testDir = tempDirs.create();
        createPubspecYaml(testDir);
        createProjectConfig(ProjectConfig(), testDir);

        final project = runner.context.get<ProjectService>().findAncestor(
              directory: testDir,
            );
        final cacheVersion = createCacheVersion('3.10.0');

        // Create context with privilegedAccess set to false
        final nonPrivilegedContext = TestFactory.context(
          privilegedAccess: false,
        );

        final workflow = UpdateProjectReferencesWorkflow(nonPrivilegedContext);

        // Run workflow
        await workflow.call(project, cacheVersion, force: true);

        // Version files should still be created
        final versionFile = File(
          p.join(
            testDir.path,
            '.fvm',
            UpdateProjectReferencesWorkflow.versionFile,
          ),
        );
        expect(versionFile.existsSync(), isTrue);

        // But symlinks should not be created
        final flutterSdkLink = Link(
          p.join(
            testDir.path,
            '.fvm',
            UpdateProjectReferencesWorkflow.flutterSdkLink,
          ),
        );
        expect(flutterSdkLink.existsSync(), isFalse);
      },
    );

    test('should clean up and recreate existing symlinks', () async {
      // Skip on Windows where symlinks require admin rights
      if (Platform.isWindows) {
        return;
      }

      final testDir = tempDirs.create();
      createPubspecYaml(testDir);
      createProjectConfig(ProjectConfig(), testDir);

      // Create initial .fvm directory with symlinks
      final fvmDir = Directory(p.join(testDir.path, '.fvm'));
      fvmDir.createSync();

      // Create a temporary directory to initially link to
      final tempDir = tempDirs.create();

      // Create initial symlink pointing to temp directory
      final flutterSdkLink = Link(
        p.join(fvmDir.path, UpdateProjectReferencesWorkflow.flutterSdkLink),
      );
      flutterSdkLink.createSync(tempDir.path);

      expect(flutterSdkLink.existsSync(), isTrue);
      expect(flutterSdkLink.targetSync(), equals(tempDir.path));

      // Now run the workflow with a different target
      final project = runner.context.get<ProjectService>().findAncestor(
            directory: testDir,
          );
      final cacheVersion = createCacheVersion('3.10.0');

      final workflow = UpdateProjectReferencesWorkflow(runner.context);
      await workflow.call(project, cacheVersion, force: true);

      // Verify the symlink now points to the new location
      expect(flutterSdkLink.existsSync(), isTrue);
      expect(flutterSdkLink.targetSync(), equals(cacheVersion.directory));
    });

    test('should handle file system errors gracefully', () async {
      // Skip on Windows where file permissions are different
      if (Platform.isWindows) {
        return;
      }

      final testDir = tempDirs.create();
      createPubspecYaml(testDir);
      createProjectConfig(ProjectConfig(), testDir);

      // Create an unwritable .fvm directory to cause errors
      final fvmDir = Directory(p.join(testDir.path, '.fvm'));
      fvmDir.createSync();

      // Make the directory read-only
      await Process.run('chmod', ['555', fvmDir.path]);

      try {
        final project = runner.context.get<ProjectService>().findAncestor(
              directory: testDir,
            );
        final cacheVersion = createCacheVersion('3.10.0');

        final workflow = UpdateProjectReferencesWorkflow(runner.context);

        // Should throw an exception due to permission error
        expect(
          () => workflow.call(project, cacheVersion, force: true),
          throwsA(isA<AppDetailedException>()),
        );
      } finally {
        // Restore permissions for cleanup
        await Process.run('chmod', ['755', fvmDir.path]);
      }
    });

    test('should correctly handle fork version references', () async {
      // Skip on Windows where symlinks require admin rights
      if (Platform.isWindows) {
        return;
      }

      final testDir = tempDirs.create();
      createPubspecYaml(testDir, name: 'test_project');
      createProjectConfig(ProjectConfig(), testDir);

      final project = runner.context.get<ProjectService>().findAncestor(
            directory: testDir,
          );

      // Create a fork version (e.g., my-fork/3.10.0)
      const forkName = 'my-fork';
      const versionName = '3.10.0';
      final forkVersionDir = Directory(
        p.join(cacheDir.path, 'versions', forkName, versionName),
      );
      forkVersionDir.createSync(recursive: true);

      // Create bin directory
      final binDir = Directory(p.join(forkVersionDir.path, 'bin'));
      binDir.createSync(recursive: true);

      // Create dart-sdk cache directory
      final dartSdkDir = Directory(p.join(binDir.path, 'cache', 'dart-sdk'));
      dartSdkDir.createSync(recursive: true);

      // Create version files
      File(
        p.join(forkVersionDir.path, 'version'),
      ).writeAsStringSync(versionName);
      File(p.join(dartSdkDir.path, 'version')).writeAsStringSync('2.19.0');

      // Create a fork FlutterVersion
      final flutterVersion = FlutterVersion.parse('$forkName/$versionName');
      expect(flutterVersion.fromFork, isTrue);
      expect(flutterVersion.fork, equals(forkName));
      expect(flutterVersion.name, equals(versionName));
      expect(flutterVersion.nameWithAlias, equals('$forkName/$versionName'));

      final cacheVersion = CacheFlutterVersion.fromVersion(
        flutterVersion,
        directory: forkVersionDir.path,
      );

      // Ensure context has privilegedAccess set to true
      final privilegedContext = TestFactory.context(privilegedAccess: true);
      final workflow = UpdateProjectReferencesWorkflow(privilegedContext);

      // Run workflow
      final updatedProject = await workflow.call(
        project,
        cacheVersion,
        force: true,
      );

      // Verify the project was updated with the correct fork version
      expect(updatedProject.pinnedVersion?.fromFork, isTrue);
      expect(updatedProject.pinnedVersion?.fork, equals(forkName));
      expect(updatedProject.pinnedVersion?.name, equals(versionName));
      expect(
        updatedProject.pinnedVersion?.nameWithAlias,
        equals('$forkName/$versionName'),
      );

      // Verify config file contains the full fork version string
      final configFile = File(p.join(testDir.path, '.fvmrc'));
      expect(configFile.existsSync(), isTrue);
      final configContent = configFile.readAsStringSync();
      expect(configContent, contains('$forkName/$versionName'));

      // Verify symlink was created in the correct fork subdirectory
      final versionSymlink = Link(
        p.join(testDir.path, '.fvm', 'versions', forkName, versionName),
      );
      expect(versionSymlink.existsSync(), isTrue);
      expect(versionSymlink.targetSync(), equals(cacheVersion.directory));

      // Verify flutter_sdk symlink points to the fork version
      final flutterSdkLink = Link(
        p.join(
          testDir.path,
          '.fvm',
          UpdateProjectReferencesWorkflow.flutterSdkLink,
        ),
      );
      expect(flutterSdkLink.existsSync(), isTrue);
      expect(flutterSdkLink.targetSync(), equals(cacheVersion.directory));
    });

    test('should update flavor with fork version', () async {
      final testDir = tempDirs.create();
      createPubspecYaml(testDir);
      createProjectConfig(ProjectConfig(), testDir);

      final project = runner.context.get<ProjectService>().findAncestor(
            directory: testDir,
          );

      // Create a fork version
      const forkName = 'my-fork';
      const versionName = '3.10.0';
      final forkVersionDir = Directory(
        p.join(cacheDir.path, 'versions', forkName, versionName),
      );
      forkVersionDir.createSync(recursive: true);

      // Create version file
      File(
        p.join(forkVersionDir.path, 'version'),
      ).writeAsStringSync(versionName);

      final flutterVersion = FlutterVersion.parse('$forkName/$versionName');
      final cacheVersion = CacheFlutterVersion.fromVersion(
        flutterVersion,
        directory: forkVersionDir.path,
      );

      final workflow = UpdateProjectReferencesWorkflow(runner.context);

      // Run workflow with flavor
      final updatedProject = await workflow.call(
        project,
        cacheVersion,
        flavor: 'staging',
        force: true,
      );

      // Verify flavor contains the full fork version string
      final flavor = updatedProject.flavors['staging'];
      expect(flavor, equals('$forkName/$versionName'));
    });

    test('should handle project constraints issues', () async {
      final testDir = tempDirs.create();
      createPubspecYaml(
        testDir,
        name: 'test_project',
        sdkConstraint: '>=3.1.0 <4.0.0',
      );

      createProjectConfig(ProjectConfig(), testDir);

      final cacheVersion = MockCacheFlutterVersion();

      when(() => cacheVersion.dartSdkVersion).thenReturn('2.19.0');
      when(() => cacheVersion.flutterSdkVersion).thenReturn('2.19.0');
      when(() => cacheVersion.name).thenReturn('2.19.0');
      when(() => cacheVersion.nameWithAlias).thenReturn('2.19.0');
      when(() => cacheVersion.fromFork).thenReturn(false);

      when(() => cacheVersion.printFriendlyName).thenReturn('Mock version');

      when(() => cacheVersion.directory).thenReturn(tempDirs.create().path);

      final project = runner.context.get<ProjectService>().findAncestor(
            directory: testDir,
          );

      final workflow = UpdateProjectReferencesWorkflow(runner.context);

      // With force=true, it should skip confirmation
      final result = await workflow.call(project, cacheVersion, force: true);
      expect(result, isA<Project>());
    });
  });
}

class MockCacheFlutterVersion extends Mock implements CacheFlutterVersion {}
