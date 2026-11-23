# FVM Testing Methodology Guide

## Test Layers

### Mocked Fast Layer

Paths:
- `test/**/*.dart`, excluding tests tagged `sdk`, `network`, `git`, `integration`, or `migration`.
- `test/testing_helpers/` fixtures and fakes.

Run:

```bash
dart test -x "sdk || network || git || integration || migration"
```

Use:
- `TestFactory.fastContext()`
- `TestFactory.fastCommandRunner()`
- `FakeFlutterService`
- `FakeFlutterReleaseClient`
- `FakeGitService`
- `FakeFlutterSdkFixture`

This layer proves command/workflow logic, parsing, local file effects, cache bookkeeping, fake SDK setup states, and happy-path plumbing in seconds. It does not prove real Git clones, real Flutter SDK setup, live network behavior, recovery from real corrupt caches, or concurrency against real installed SDKs.

### Real Integration Layer

Paths and commands:
- `fvm integration-test`
- `dart run grinder integration-test`
- `test/integration/`
- CI jobs: `integration-test` and `migration-test`

This layer proves real clone/install/setup/recovery/global-link behavior. It is slow and can mutate the real FVM cache, so local runs require deliberate intent.

### Manual Drift Guard

Run the live release-schema drift guard on demand:

```bash
dart test -t network
```

The guard checks that production release parsing still accepts live Flutter release metadata and that current channel releases still carry modern SDK metadata not represented in the minimal fixture.

## Fast Test Setup

Prefer the fast factory for ordinary command and workflow tests:

```dart
final runner = TestFactory.fastCommandRunner();

final exitCode = await runner.run(['fvm', 'install', '3.10.0']);

expect(exitCode, ExitCode.success.code);
```

Use a fast context when you need direct service access:

```dart
final context = TestFactory.fastContext();
final flutter = context.get<FlutterService>() as FakeFlutterService;
```

The fast factory wires:
- `FlutterService` to `FakeFlutterService`
- `FlutterReleaseClient` to `FakeFlutterReleaseClient`
- `GitService` to `FakeGitService`

Use `TestFactory.context()` only when you need the default lower-level test context or custom generators.

## Fake SDK States

`FakeFlutterSdkFixture.install()` writes fixture-backed SDK layouts under the isolated test cache.

States:
- `installedNotSetup`: root `version` file and executables only.
- `installedSetup`: version metadata plus Dart SDK cache files.
- `versionMismatch`: legacy `version` and JSON metadata intentionally disagree.
- `invalidExecutable`: SDK layout without the Flutter executable.

Example:

```dart
FakeFlutterSdkFixture.install(
  context,
  FlutterVersion.parse('3.10.0'),
  state: FakeFlutterSdkState.installedSetup,
);
```

Fixture resolution intentionally keeps a fallback for versions without dedicated root fixtures. Tests still install versions such as `2.0.0`, `3.0.0`, and commit refs through that fallback.

## Release Fixtures

The fast release client reads `test/fixtures/releases/minimal_releases.json`. Fake install validation derives allowed release versions from that fixture, so the fixture is the single source of truth.

When the production release schema changes:
1. Run `dart test -t network`.
2. Update `minimal_releases.json` only if the fast layer needs the new schema.
3. Add or update fast assertions that would fail on fixture drift.

## Recording Root Fixtures

Use the fixture recorder when a fake SDK layout needs new root metadata:

```bash
dart test test/testing_helpers/record_test_fixtures_test.dart
```

The recorder workflow should preserve:
- legacy root `version`
- `bin/cache/flutter.version.json`
- Dart SDK version metadata
- normalized, deterministic JSON output

## Test Isolation Rules

Do:
- Create fresh contexts per test.
- Use `workingDirectoryOverride` instead of mutating `Directory.current`.
- Keep global config writes routed through `FvmContext.appConfigPath`.
- Use test-scoped config paths under the test temp root.
- Clean up temp resources through the shared test utilities.

Do not:
- Read or write the real `LocalAppConfig` from fast tests.
- Depend on the process-wide current directory.
- Reach real Git, Flutter, or network services from untagged fast tests.
- Share mutable fake service instances between unrelated tests.

## Command Test Pattern

```dart
void main() {
  late TestCommandRunner runner;

  setUp(() {
    runner = TestFactory.fastCommandRunner();
  });

  test('installs a fixture-backed release', () async {
    final exitCode = await runner.run(['fvm', 'install', '3.10.0']);

    expect(exitCode, ExitCode.success.code);

    final cacheService = runner.context.get<CacheService>();
    final version = FlutterVersion.parse('3.10.0');
    expect(cacheService.getVersion(version), isNotNull);
  });
}
```

## User Input Tests

Use `TestLogger` for prompts:

```dart
final context = TestFactory.fastContext(
  generators: {
    Logger: (context) => TestLogger(context)
      ..setConfirmResponse('Would you like to continue?', true),
  },
);

final runner = TestFactory.fastCommandRunner(context: context);
```

## Tags

Use tags to keep the fast layer clean:
- `network`: live HTTP or release metadata.
- `git`: real Git behavior.
- `sdk`: real or local Flutter SDK behavior.
- `integration`: broad real integration workflows.
- `migration`: v3-to-v4 migration coverage.

The default fast command excludes all of those tags.

## Verification Checklist

Before pushing:

```bash
dart analyze --fatal-infos
dart test -x "sdk || network || git || integration || migration"
```

For release-schema drift:

```bash
dart test -t network
```

For real integration proof, prefer CI unless you explicitly accept the local cache impact:

```bash
dart run grinder integration-test
```
