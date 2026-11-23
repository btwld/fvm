---
id: manual-smoke-test
title: Manual Branch Smoke Test
---

# Manual Branch Smoke Test

Use this when an agent needs a quick end-to-end check of the current FVM branch without running the destructive real integration suite.

This smoke test runs the branch CLI through a throwaway project and isolated cache. It uses a local fake Flutter Git remote, so it proves FVM command wiring, git-cache creation, install, project `use`, prompt handling, project file writes, symlink creation, Melos/VS Code settings, and `fvm flutter` proxy behavior without cloning the real Flutter repository.

## When To Run

Run this before handoff when changes touch:

- `GitService`
- `FlutterService`
- `EnsureCacheWorkflow`
- install/use/global command behavior
- project reference or SDK symlink behavior
- project registry tracking or unused-SDK classification in `fvm list`
- non-interactive prompt handling
- `.fvmrc`, `.gitignore`, Melos, or VS Code project updates

This does not replace `dart test` or the real `fvm integration-test`. It is a fast manual confidence check between unit tests and the full destructive integration suite.

## Safety

The script sets:

- `HOME` to a temp directory
- `FVM_CACHE_PATH` to a temp cache
- `FVM_GIT_CACHE_PATH` to a temp bare git cache
- `FVM_FLUTTER_URL` to a local `file://` Git URL
- `FVM_USE_GIT_CACHE=true`

It also unsets FVM's recognized CI environment variables so project tracking
runs during the smoke test.

It should not mutate the user's normal FVM cache or global config. The temp directory is left in place for inspection and printed as `Smoke root`; remove it manually after reviewing.

`FVM_FLUTTER_URL` must be a valid Git URL. Use a `file://` URL for local remotes; a plain filesystem path is rejected by FVM URL validation.

The SDK install, git cache, home directory, generated project, `.fvmrc`,
`.gitignore`, VS Code settings, and Melos settings all live under the printed
`Smoke root`. The install path is `$ROOT/fvm-cache/versions/stable`, not the
user's normal FVM cache.

The script uses `expect` for the interactive Melos confirmation path. macOS includes `/usr/bin/expect`; install it first if another environment does not have it.

## Command

Run from the repository root:

```bash
set -euo pipefail

command -v expect >/dev/null || {
  echo "expect is required for the interactive Melos prompt check" >&2
  exit 1
}

FVM_REPO="$(pwd)"
ROOT="$(mktemp -d /tmp/fvm-branch-smoke.XXXXXX)"
MARKER="$ROOT/.fvm-smoke-root"
FAKE_REMOTE_WORK="$ROOT/flutter_seed"
FAKE_REMOTE_BARE="$ROOT/flutter_remote.git"
CACHE="$ROOT/fvm-cache"
GIT_CACHE="$ROOT/cache.git"
PROJECT="$ROOT/app"
HOME_DIR="$ROOT/home"

: > "$MARKER"

mkdir -p \
  "$FAKE_REMOTE_WORK/bin" \
  "$FAKE_REMOTE_WORK/bin/cache/dart-sdk/bin" \
  "$PROJECT/.vscode" \
  "$HOME_DIR"

cd "$FAKE_REMOTE_WORK"
git init -b stable >/dev/null
git config user.email smoke@fvm.app
git config user.name "FVM Smoke"

printf '3.99.0-smoke\n' > version
printf '#!/usr/bin/env sh\necho "Flutter smoke 3.99.0 on stable"\n' > bin/flutter
printf '#!/usr/bin/env sh\necho "Dart smoke 3.99.0"\n' > bin/dart
printf '#!/usr/bin/env sh\necho "Dart smoke 3.99.0"\n' > bin/cache/dart-sdk/bin/dart
chmod +x bin/flutter bin/dart bin/cache/dart-sdk/bin/dart

git add . >/dev/null
git commit -m 'seed fake flutter' >/dev/null
BASE_SHA="$(git rev-parse HEAD)"
git tag smoke-tag "$BASE_SHA"

git checkout --detach >/dev/null 2>&1
printf 'hidden-only\n' > hidden_ref_only
git add hidden_ref_only >/dev/null
git commit -m 'seed hidden-only ref' >/dev/null
HIDDEN_SHA="$(git rev-parse HEAD)"
git update-ref refs/pull/1/head "$HIDDEN_SHA"
git checkout stable >/dev/null 2>&1
git branch beta stable

git clone --bare "$FAKE_REMOTE_WORK" "$FAKE_REMOTE_BARE" >/dev/null 2>&1
git --git-dir="$FAKE_REMOTE_BARE" symbolic-ref HEAD refs/heads/stable
git --git-dir="$FAKE_REMOTE_BARE" update-ref refs/pull/1/head "$HIDDEN_SHA"

REMOTE_URL="file://$FAKE_REMOTE_BARE"

cd "$PROJECT"
printf 'name: fvm_smoke_app\nenvironment:\n  sdk: ">=3.6.0 <4.0.0"\n' > pubspec.yaml
printf 'name: fvm_smoke_workspace\npackages:\n  - .\n' > melos.yaml
: > .gitignore

run_fvm_skip() {
  env \
    -u CI \
    -u TRAVIS \
    -u CIRCLECI \
    -u GITHUB_ACTIONS \
    -u GITLAB_CI \
    -u JENKINS_URL \
    -u BAMBOO_BUILD_NUMBER \
    -u TEAMCITY_VERSION \
    -u TF_BUILD \
    HOME="$HOME_DIR" \
    FVM_CACHE_PATH="$CACHE" \
    FVM_GIT_CACHE_PATH="$GIT_CACHE" \
    FVM_FLUTTER_URL="$REMOTE_URL" \
    FVM_USE_GIT_CACHE=true \
    dart run "$FVM_REPO/bin/main.dart" --fvm-skip-input "$@"
}

run_fvm_interactive_with_yes() {
  SMOKE_HOME="$HOME_DIR" \
  SMOKE_CACHE="$CACHE" \
  SMOKE_GIT_CACHE="$GIT_CACHE" \
  SMOKE_REMOTE_URL="$REMOTE_URL" \
  SMOKE_REPO="$FVM_REPO" \
  expect <<'EOF'
set timeout 90
set main [file join $env(SMOKE_REPO) bin main.dart]
spawn env \
  -u CI \
  -u TRAVIS \
  -u CIRCLECI \
  -u GITHUB_ACTIONS \
  -u GITLAB_CI \
  -u JENKINS_URL \
  -u BAMBOO_BUILD_NUMBER \
  -u TEAMCITY_VERSION \
  -u TF_BUILD \
  "HOME=$env(SMOKE_HOME)" \
  "FVM_CACHE_PATH=$env(SMOKE_CACHE)" \
  "FVM_GIT_CACHE_PATH=$env(SMOKE_GIT_CACHE)" \
  "FVM_FLUTTER_URL=$env(SMOKE_REMOTE_URL)" \
  "FVM_USE_GIT_CACHE=true" \
  dart run $main use stable --force --skip-setup --skip-pub-get
expect {
  "Would you like to configure melos.yaml to use FVM-managed Flutter SDK?" { send "y\r" }
  timeout { puts "Timed out waiting for Melos prompt"; exit 124 }
}
expect eof
catch wait result
exit [lindex $result 3]
EOF
}

printf '\n== fvm version ==\n'
run_fvm_skip --version

printf '\n== install stable --no-setup ==\n'
run_fvm_skip install stable --no-setup

printf '\n== use stable, non-interactive default prompt path ==\n'
USE_SKIP_OUTPUT="$(run_fvm_skip use stable --force --skip-setup --skip-pub-get 2>&1)"
printf '%s\n' "$USE_SKIP_OUTPUT"
case "$USE_SKIP_OUTPUT" in
  *"Would you like to configure melos.yaml to use FVM-managed Flutter SDK?"*) ;;
  *) echo "Melos prompt was not emitted under skip input" >&2; exit 1 ;;
esac
case "$USE_SKIP_OUTPUT" in
  *"Skipping input confirmation"*) ;;
  *) echo "Skip-input confirmation warning was not emitted" >&2; exit 1 ;;
esac
case "$USE_SKIP_OUTPUT" in
  *"Using default value of false"*) ;;
  *) echo "Skip-input default value was not reported as false" >&2; exit 1 ;;
esac
if grep -Fq 'sdkPath:' melos.yaml; then
  echo "melos.yaml changed even though skip-input default is false" >&2
  exit 1
fi

test -f .fvmrc
grep -Fq '"flutter": "stable"' .fvmrc
test -f .fvm/fvm_config.json
grep -Fq '"flutterSdkVersion": "stable"' .fvm/fvm_config.json
test -f .fvm/version
grep -Fxq '3.99.0-smoke' .fvm/version
test -f .fvm/release
grep -Fxq 'stable' .fvm/release

test -L .fvm/flutter_sdk
FLUTTER_SDK_TARGET="$(readlink .fvm/flutter_sdk)"
case "$FLUTTER_SDK_TARGET" in
  "$CACHE/versions/stable") ;;
  *) echo "Unexpected flutter_sdk symlink target: $FLUTTER_SDK_TARGET" >&2; exit 1 ;;
esac

test -L .fvm/versions/stable
VERSION_LINK_TARGET="$(readlink .fvm/versions/stable)"
case "$VERSION_LINK_TARGET" in
  "$CACHE/versions/stable") ;;
  *) echo "Unexpected version symlink target: $VERSION_LINK_TARGET" >&2; exit 1 ;;
esac

grep -Fxq '.fvm/' .gitignore
grep -Fq '"dart.flutterSdkPath": ".fvm/versions/stable"' .vscode/settings.json

printf '\n== use stable, interactive yes prompt path ==\n'
run_fvm_interactive_with_yes
grep -Fq 'sdkPath: .fvm/flutter_sdk' melos.yaml

printf '\n== fvm flutter --version ==\n'
FLUTTER_OUTPUT="$(run_fvm_skip flutter --version)"
printf '%s\n' "$FLUTTER_OUTPUT"
case "$FLUTTER_OUTPUT" in
  *"Flutter smoke 3.99.0"*) ;;
  *) echo "Unexpected flutter output" >&2; exit 1 ;;
esac

printf '\n== fvm list ==\n'
LIST_OUTPUT="$(run_fvm_skip list)"
printf '%s\n' "$LIST_OUTPUT"
case "$LIST_OUTPUT" in
  *"$CACHE/versions"*) ;;
  *) echo "fvm list did not use the isolated cache path" >&2; exit 1 ;;
esac
case "$LIST_OUTPUT" in
  *"stable"*) ;;
  *) echo "fvm list did not include stable" >&2; exit 1 ;;
esac
case "$LIST_OUTPUT" in
  *"3.99.0-smoke"*) ;;
  *) echo "fvm list did not include the fake Flutter version" >&2; exit 1 ;;
esac

printf '\n== project registry ==\n'
test -f "$CACHE/projects.json"
grep -Fq "$PROJECT" "$CACHE/projects.json"

printf '\n== install beta --no-setup for unused classification ==\n'
run_fvm_skip install beta --no-setup

printf '\n== fvm list unused ==\n'
LIST_AFTER_BETA="$(run_fvm_skip list)"
printf '%s\n' "$LIST_AFTER_BETA"
case "$LIST_AFTER_BETA" in
  *"Unused"*) ;;
  *) echo "fvm list did not classify the unused beta SDK" >&2; exit 1 ;;
esac
case "$LIST_AFTER_BETA" in
  *"no project known to FVM pins that SDK"*) ;;
  *) echo "fvm list did not explain the Unused label" >&2; exit 1 ;;
esac
case "$LIST_AFTER_BETA" in
  *"fvm cleanup"*) ;;
  *) echo "fvm list did not point to fvm cleanup" >&2; exit 1 ;;
esac

printf '\n== fvm api list ==\n'
API_LIST="$(run_fvm_skip api list --compress --skip-size-calculation)"
printf '%s\n' "$API_LIST"
case "$API_LIST" in
  *"$PROJECT"*) ;;
  *) echo "fvm api list did not include the smoke project path" >&2; exit 1 ;;
esac
case "$API_LIST" in
  *'"unreferencedVersions":["beta"]'*) ;;
  *) echo "fvm api list did not list beta in unreferencedVersions" >&2; exit 1 ;;
esac
printf '%s\n' "$API_LIST" | python3 -c 'import json,sys; json.load(sys.stdin)'

printf '\n== fvm api cleanup ==\n'
API_CLEANUP="$(run_fvm_skip api cleanup --compress)"
printf '%s\n' "$API_CLEANUP"
case "$API_CLEANUP" in
  *'"unused":["beta"]'*) ;;
  *) echo "fvm api cleanup did not list beta as unused" >&2; exit 1 ;;
esac
printf '%s\n' "$API_CLEANUP" | python3 -c 'import json,sys; json.load(sys.stdin)'

printf '\n== fvm cleanup preview ==\n'
CLEANUP_OUTPUT="$(run_fvm_skip cleanup)"
printf '%s\n' "$CLEANUP_OUTPUT"
case "$CLEANUP_OUTPUT" in
  *'beta'*) ;;
  *) echo "fvm cleanup did not identify beta" >&2; exit 1 ;;
esac
test -d "$CACHE/versions/beta"

printf '\n== fvm cleanup removal ==\n'
run_fvm_skip cleanup --remove-unused --yes
test ! -d "$CACHE/versions/beta"

printf '\n== project files ==\n'
printf '.fvmrc:\n'
sed -n '1,20p' .fvmrc
printf '\n'
printf '.fvm/fvm_config.json:\n'
sed -n '1,20p' .fvm/fvm_config.json
printf '\n'
printf '.fvm/version: '
cat .fvm/version
printf '\n'
printf '.fvm/release: '
cat .fvm/release
printf '\n'
printf 'flutter_sdk -> %s\n' "$FLUTTER_SDK_TARGET"
printf 'version link -> %s\n' "$VERSION_LINK_TARGET"
printf '.gitignore:\n'
sed -n '1,20p' .gitignore
printf '\n'
printf '.vscode/settings.json:\n'
sed -n '1,40p' .vscode/settings.json
printf '\n'
printf 'melos.yaml:\n'
sed -n '1,40p' melos.yaml
printf '\n'

printf '\n== git cache checks ==\n'
test "$(git --git-dir="$GIT_CACHE" rev-parse --is-bare-repository)" = true

HEAD_REF="$(git --git-dir="$GIT_CACHE" symbolic-ref --quiet HEAD)"
printf 'HEAD=%s\n' "$HEAD_REF"
case "$HEAD_REF" in
  refs/heads/*) ;;
  *) echo "Cache HEAD is not a branch" >&2; exit 1 ;;
esac
git --git-dir="$GIT_CACHE" show-ref --verify --quiet "$HEAD_REF"

REFS="$(git --git-dir="$GIT_CACHE" for-each-ref --format='%(refname)')"
printf '%s\n' "$REFS"
if printf '%s\n' "$REFS" | grep -Ev '^(refs/heads/|refs/tags/)' >/dev/null; then
  echo "Unexpected non heads/tags ref in git cache" >&2
  exit 1
fi
git --git-dir="$GIT_CACHE" show-ref --verify --quiet refs/tags/smoke-tag
if git --git-dir="$GIT_CACHE" show-ref --verify --quiet refs/pull/1/head; then
  echo "Unexpected hidden pull ref in git cache" >&2
  exit 1
fi
if git --git-dir="$GIT_CACHE" cat-file -e "$HIDDEN_SHA^{commit}" 2>/dev/null; then
  echo "Unexpected hidden-only commit object in git cache" >&2
  exit 1
fi

FETCH_SPECS="$(git --git-dir="$GIT_CACHE" config --get-all remote.origin.fetch | sort)"
printf 'fetch specs:\n%s\n' "$FETCH_SPECS"
FETCH_SPEC_COUNT="$(printf '%s\n' "$FETCH_SPECS" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
test "$FETCH_SPEC_COUNT" = 2
printf '%s\n' "$FETCH_SPECS" | grep -Fqx '+refs/heads/*:refs/heads/*'
printf '%s\n' "$FETCH_SPECS" | grep -Fqx '+refs/tags/*:refs/tags/*'

TAG_OPTS="$(git --git-dir="$GIT_CACHE" config --get-all remote.origin.tagOpt)"
TAG_OPT_COUNT="$(printf '%s\n' "$TAG_OPTS" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
test "$TAG_OPT_COUNT" = 1
test "$TAG_OPTS" = '--no-tags'

if git --git-dir="$GIT_CACHE" config --get remote.origin.mirror >/dev/null; then
  echo "Unexpected mirror config" >&2
  exit 1
fi

git --git-dir="$GIT_CACHE" fsck --connectivity-only >/dev/null

printf '\nSmoke root: %s\n' "$ROOT"
```

## Expected Result

The command must exit `0`.

Expected high-signal output:

- `fvm --version` prints the branch package version.
- `install stable --no-setup` creates the local git cache and installs `stable`.
- The first `use stable --force --skip-setup --skip-pub-get` run uses `--fvm-skip-input`, emits the Melos prompt text, logs `Skipping input confirmation`, and keeps `melos.yaml` unchanged because the Melos confirmation default is `false`.
- The second `use stable --force --skip-setup --skip-pub-get` run answers the Melos prompt with `yes` through `expect` and writes `sdkPath: .fvm/flutter_sdk`.
- `fvm flutter --version` prints `Flutter smoke 3.99.0 on stable`.
- `fvm list` reports the isolated temp cache, `stable`, and `3.99.0-smoke`.
- `use` creates `$CACHE/projects.json` containing the smoke project path.
- `fvm list` labels the unused `beta` SDK `Unused`, explains that only projects known to FVM are considered, and points to `fvm cleanup`.
- `fvm api list --compress --skip-size-calculation` prints valid JSON with the smoke project under `projects` and `unreferencedVersions: ["beta"]`.
- `fvm api cleanup --compress` prints valid JSON with `unused: ["beta"]`.
- `fvm cleanup` previews `beta` without removing it.
- `fvm cleanup --remove-unused --yes` removes only the unused `beta` SDK.
- `.fvmrc` contains `"flutter": "stable"`.
- `.fvm/fvm_config.json` contains `"flutterSdkVersion": "stable"`.
- `.fvm/version` contains `3.99.0-smoke`.
- `.fvm/release` contains `stable`.
- `.fvm/flutter_sdk` points to the isolated temp cache.
- `.fvm/versions/stable` points to the isolated temp cache.
- `.gitignore` contains `.fvm/`.
- `.vscode/settings.json` contains `"dart.flutterSdkPath": ".fvm/versions/stable"`.
- `melos.yaml` contains `sdkPath: .fvm/flutter_sdk`.
- `cache.git` is bare.
- `cache.git` `HEAD` is under `refs/heads/`.
- `cache.git` `HEAD` points at an existing branch ref.
- `cache.git` includes the fake tag `refs/tags/smoke-tag`.
- `cache.git` excludes the fake hidden ref `refs/pull/1/head` and its hidden-only commit object.
- `remote.origin.fetch` contains only:
  - `+refs/heads/*:refs/heads/*`
  - `+refs/tags/*:refs/tags/*`
- `remote.origin.tagOpt` is exactly one `--no-tags` value.
- `remote.origin.mirror` is absent.
- `git fsck --connectivity-only` passes.

## Coverage Boundaries

This smoke test should stay fast and isolated. It does not replace the targeted
tests for stale cache clone fallback, missing-object fallback, invalid-cache
recreation, cache migration, or real Flutter SDK setup. Keep running the focused
unit/integration tests for those paths when touching `GitService`,
`FlutterService`, or `EnsureCacheWorkflow`.

## Cleanup

After inspection, remove only the exact temp root printed by the run. Do not use
`fvm remove`, `fvm destroy`, or ad hoc cache deletion for this cleanup, because
running those outside the script environment could target the user's real FVM
configuration.

```bash
SMOKE_ROOT="/tmp/fvm-branch-smoke.<suffix>"

case "$SMOKE_ROOT" in
  /tmp/fvm-branch-smoke.*) ;;
  *) echo "Refusing to remove unexpected path: $SMOKE_ROOT" >&2; exit 1 ;;
esac

test -f "$SMOKE_ROOT/.fvm-smoke-root"

rm -rf "$SMOKE_ROOT"
```

This removes the fake Flutter remote, isolated FVM home, isolated SDK install,
isolated git cache, and throwaway project/config updates created by the smoke
test. It should not remove anything outside the temp root.

For older runs where only the suffix is known:

```bash
rm -rf /tmp/fvm-branch-smoke.<suffix>
```

Use the exact `Smoke root` path printed by the run.

## When To Escalate To Real Integration

Run the real integration workflow instead when you need proof against live Flutter infrastructure, real SDK setup, `flutter doctor`, destructive cleanup, concurrency, or global symlink behavior:

```bash
dart run grinder integration-test
```

That workflow is intentionally slower and can mutate the real FVM cache. See `integration-tests.md` before running it locally.
