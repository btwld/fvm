import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:fvm_release_tool/src/chocolatey_package.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  const version = '4.1.2';

  late Directory repoRoot;

  setUp(() {
    repoRoot = Directory.systemTemp.createTempSync('chocolatey_package_test_');
    addTearDown(() {
      if (repoRoot.existsSync()) {
        repoRoot.deleteSync(recursive: true);
      }
    });

    File(p.join(repoRoot.path, 'fvm.nuspec')).writeAsStringSync('''
<package>
  <metadata>
    <id>fvm</id>
    <version>\$version\$</version>
  </metadata>
  <files>
    <file src="tools\\**" target="tools" />
  </files>
</package>
''');
  });

  test('stages the precompiled executable, license, and nuspec', () {
    _writeReleaseArchive(repoRoot, version: version);

    final files = stageChocolateyPackage(repoRoot: repoRoot, version: version);

    expect(files.executable.readAsBytesSync(), [1, 2, 3]);
    expect(files.license.readAsStringSync(), 'license');
    expect(
      files.nuspec.readAsStringSync(),
      contains('<version>\$version\$</version>'),
    );
    expect(files.nuspec.readAsStringSync(), isNot(contains('dart-sdk')));
  });

  test('writes VERIFICATION.txt with the release URL and exe hash', () {
    _writeReleaseArchive(repoRoot, version: version);

    final files = stageChocolateyPackage(repoRoot: repoRoot, version: version);
    final verification = files.verification.readAsStringSync();

    expect(p.basename(files.verification.path), 'VERIFICATION.txt');
    expect(
      verification,
      contains(
        'https://github.com/btwld/fvm/releases/download/'
        '$version/fvm-$version-windows-x64.zip',
      ),
    );
    expect(
      verification,
      contains('SHA256: ${sha256.convert([1, 2, 3]).toString().toUpperCase()}'),
    );
  });

  test('fails when the Windows x64 release archive is missing', () {
    expect(
      () => stageChocolateyPackage(repoRoot: repoRoot, version: version),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('pkg-standalone-windows-x64'),
        ),
      ),
    );
  });

  test('fails when the release archive has no native executable', () {
    _writeReleaseArchive(repoRoot, version: version, includeExecutable: false);

    expect(
      () => stageChocolateyPackage(repoRoot: repoRoot, version: version),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('fvm/fvm.exe'),
        ),
      ),
    );
  });

  test('rejects a nuspec that depends on the standalone Dart SDK', () {
    _writeReleaseArchive(repoRoot, version: version);
    File(p.join(repoRoot.path, 'fvm.nuspec')).writeAsStringSync('''
<package>
  <metadata>
    <id>fvm</id>
    <dependency id="dart-sdk" version="[3.13.0]" />
  </metadata>
</package>
''');

    expect(
      () => stageChocolateyPackage(repoRoot: repoRoot, version: version),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('must not depend'),
        ),
      ),
    );
  });
}

void _writeReleaseArchive(
  Directory repoRoot, {
  required String version,
  bool includeExecutable = true,
}) {
  final archive = Archive();
  if (includeExecutable) {
    archive.addFile(ArchiveFile('fvm/fvm.exe', 3, [1, 2, 3]));
  }
  archive.addFile(
    ArchiveFile('fvm/src/LICENSE', 'license'.length, 'license'.codeUnits),
  );

  final archiveFile = File(
    p.join(repoRoot.path, 'build', 'fvm-$version-windows-x64.zip'),
  )..createSync(recursive: true);
  archiveFile.writeAsBytesSync(ZipEncoder().encode(archive)!);
}
