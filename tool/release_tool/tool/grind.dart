import 'dart:convert';
import 'dart:io';

import 'package:cli_pkg/cli_pkg.dart' as pkg;
import 'package:fvm_release_tool/src/chocolatey_package.dart';
import 'package:grinder/grinder.dart';
import 'package:path/path.dart' as p;
import 'package:meta/meta.dart';

const _packageName = 'fvm';

// This must always name the account that *canonically* owns the repository,
// never an account that merely redirects to it.
//
// GitHub keeps redirects alive after a repository moves between accounts, so
// a stale owner here looks fine everywhere except the one call that matters:
// GET follows the redirect transparently (as do `gh` and curl), but cli_pkg
// does not follow redirects on POST, so creating the release fails with
// `307 Moved Permanently` after every test job has already passed. That is
// exactly how the v4.1.3 deploy broke while the repository was temporarily
// owned by another account.
//
// When the repository moves, update this constant in the same change.
const _owner = 'btwld';

const _repo = 'fvm';
const _chocolateyPushUrl = 'https://push.chocolatey.org/';

final Directory _releaseToolRoot = Directory.current;
final Directory _repoRoot = Directory(
  p.normalize(p.join(_releaseToolRoot.path, '..', '..')),
);

@visibleForTesting
Directory? repoRootOverride;

@visibleForTesting
Future<String> Function(Uri uri)? httpRequestOverride;

Directory get _effectiveRepoRoot => repoRootOverride ?? _repoRoot;

void main(List<String> args) {
  final enableVersionedFormula = args.contains('--versioned-formula');

  pkg.name.value = _packageName;
  pkg.humanName.value = _packageName;
  pkg.useExe.value = (_) => true;
  pkg.githubUser.value = _owner;
  pkg.githubRepo.value = '$_owner/$_packageName';
  pkg.homebrewRepo.value = '$_owner/homebrew-$_packageName';
  pkg.githubBearerToken.value = Platform.environment['GITHUB_TOKEN'];
  pkg.standaloneName.value = _packageName;

  if (enableVersionedFormula) {
    pkg.homebrewCreateVersionedFormula.value = true;
  }

  // Run all Grinder tasks from the repository root so cli_pkg works as before.
  // cli_pkg expects to find pubspec.yaml, bin/, and lib/ in the current working
  // directory. Because this grind.dart lives under tool/release_tool/, we need
  // to change to the repo root before invoking cli_pkg tasks.
  Directory.current = _effectiveRepoRoot;

  pkg.addAllTasks();
  grind(args);
}

@Task('Stage a self-contained Chocolatey package directory')
void fvmChocolateyPackage() {
  final files = stageChocolateyPackage(
    repoRoot: _effectiveRepoRoot,
    version: pkg.version.toString(),
  );
  log('Staged Chocolatey package at ${files.nuspec.parent.path}.');
}

@Task('Build the self-contained Chocolatey nupkg')
@Depends(fvmChocolateyPackage)
Future<void> fvmChocolateyPack() async {
  final buildDirectory = Directory(p.join(_effectiveRepoRoot.path, 'build'));
  final nuspec = File(p.join(buildDirectory.path, 'chocolatey', 'fvm.nuspec'));

  await runAsync(
    'choco',
    arguments: [
      'pack',
      nuspec.path,
      '--version=${pkg.version}',
      '--output-directory=${buildDirectory.path}',
      '--yes',
    ],
    quiet: false,
  );
}

@Task('Deploy the self-contained Chocolatey package')
@Depends(fvmChocolateyPack)
Future<void> fvmChocolateyDeploy() async {
  final token = Platform.environment['CHOCOLATEY_TOKEN'];
  if (token == null || token.isEmpty) {
    _fail('CHOCOLATEY_TOKEN must be set to deploy to Chocolatey.');
  }

  final nupkg = File(
    p.join(_effectiveRepoRoot.path, 'build', 'fvm.${pkg.version}.nupkg'),
  );
  if (!nupkg.existsSync()) {
    _fail('Chocolatey package not found: ${nupkg.path}');
  }

  log('Pushing ${nupkg.path} to $_chocolateyPushUrl.');
  // Use Process.start, not runAsync: runAsync logs the full command line,
  // which would print the API key in the release log.
  final process = await Process.start('choco', [
    'push',
    nupkg.path,
    '--source',
    _chocolateyPushUrl,
    '--api-key',
    token,
  ]);
  LineSplitter().bind(utf8.decoder.bind(process.stdout)).listen(log);
  LineSplitter().bind(utf8.decoder.bind(process.stderr)).listen(log);
  if (await process.exitCode != 0) {
    _fail('choco push failed.');
  }
}

@Task('Get all releases')
Future<void> getReleases() async {
  try {
    final response = await _githubRequest(
      Uri.parse(
        'https://api.github.com/repos/$_owner/$_repo/releases?per_page=100',
      ),
    );

    final dynamic decoded = jsonDecode(response);

    if (decoded is! List) {
      _fail(
        'Unexpected GitHub release response format. '
        'Expected a JSON list but received ${decoded.runtimeType}.',
      );
    }

    final buffer = StringBuffer();

    for (final release in decoded) {
      if (release is! Map<String, dynamic>) {
        log(
          'Warning: skipping unexpected release payload: '
          '$release',
        );
        continue;
      }

      final tagName = release['tag_name'] as String?;
      final date = release['published_at'] as String?;

      if (tagName == null || date == null) {
        log(
          'Warning: skipping release with missing tag/date: '
          '$release',
        );
        continue;
      }

      log('Release: $tagName, Date: $date');
      buffer.writeln('Release: $tagName, Date: $date');
    }

    final file = File(p.join(_effectiveRepoRoot.path, 'releases.txt'));
    file.writeAsStringSync(buffer.toString());
  } on FormatException catch (error) {
    _fail(
      'Failed to parse GitHub release response as JSON. '
      'Error: $error',
    );
  } on GrinderException {
    rethrow;
  } catch (error, stackTrace) {
    _fail('Failed to retrieve GitHub releases: $error\n$stackTrace');
  }
}

Future<String> _githubRequest(Uri uri) async {
  final override = httpRequestOverride;
  if (override != null) {
    return override(uri);
  }

  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/vnd.github.v3+json',
    );
    final token = Platform.environment['GITHUB_TOKEN'];
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'token $token');
    }

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode >= 400) {
      _fail(
        'GitHub request to $uri failed with status '
        '${response.statusCode}: $body',
      );
    }

    return body;
  } finally {
    client.close();
  }
}

@visibleForTesting
Future<String> githubRequestForTesting(Uri uri) => _githubRequest(uri);

bool get _hasGrinderContext {
  try {
    // Accessing grinder will throw when running outside of a Grinder task.
    context.grinder;
    return true;
  } catch (_) {
    return false;
  }
}

Never _fail(String message) {
  if (_hasGrinderContext) {
    return fail(message);
  }

  throw GrinderException(message);
}
