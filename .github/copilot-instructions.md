# Copilot Instructions for `btwld/fvm`

## Project overview
- FVM is a Dart CLI that manages Flutter SDK versions per project.
- Main architecture flow: **Commands → Workflows → Services → Models**.
- Key paths:
  - `bin/main.dart` (CLI entrypoint)
  - `lib/src/commands/` (command handlers)
  - `lib/src/workflows/` (multi-step orchestration)
  - `lib/src/services/` (core business logic)
  - `lib/src/models/` (data models, many generated with `dart_mappable`)
  - `test/` (unit + integration tests)

## First-run checklist for coding agents
1. Read `AGENTS.md` and `.context/docs/README.md`.
2. Install dependencies:
   - Root: `dart pub get`
   - Also check subprojects when touched:
     - `fvm_mcp/`: `dart pub get`
     - `tool/release_tool/`: `dart pub get` (requires Dart `>=3.8.0`)
3. Before changing code, run baseline checks (if environment supports Dart):
   - `dart analyze --fatal-infos`
   - `dcm analyze lib`
   - `dart test`
4. After changes, re-run targeted checks first, then broader checks relevant to touched areas.

## Build, test, and analysis commands
- Root project:
  - `dart pub get`
  - `dart analyze --fatal-infos`
  - `dcm analyze lib`
  - `dart test`
- Integration suite (Flutter required):
  - `dart run grinder test-setup`
  - `dart run grinder integration-test`
- Mapper/codegen (required after editing `@MappableClass()` models):
  - `dart run build_runner build --delete-conflicting-outputs`

## Repository-specific conventions
- Keep changes surgical: avoid broad refactors unless required by the issue.
- Prefer existing testing utilities (`TestFactory`, `TestCommandRunner`) and patterns in `.context/docs/testing-methodology.md`.
- Integration tests are heavyweight and network-sensitive; prefer unit/targeted tests first.
- Release tooling is separate under `tool/release_tool/` and uses a newer Dart SDK than the main repo.

## CI and workflow context
- Main validation workflow: `.github/workflows/test.yml`.
- `test.yml` ignores docs-only changes (`**/*.md`), so editing this file alone should not trigger the heavy test workflow.
- Draft pull requests run no jobs. `test.yml`, `test-install.yml`, and `test-docs.yml` include `ready_for_review` and skip every job while `github.event.pull_request.draft` is true. Push, schedule, manual dispatch, and reusable release calls still run.
- CI includes fallback install logic for DCM:
  - If `dcm` is unavailable, run `dart pub global activate dart_code_metrics` and add `$HOME/.pub-cache/bin` to `PATH`.

## Errors encountered during onboarding and workarounds
1. **Local command failure**: `dart: command not found`
   - Seen when running `dart pub get`, `dart analyze --fatal-infos`, and `dart test` in this environment.
   - Workaround: install/setup Dart before validation (CI uses `dart-lang/setup-dart`; locally ensure `dart --version` works, then rerun commands).
2. **GitHub Actions log retrieval limitation for a failed run**:
   - `get_workflow_run_logs_url` returned `404 Not Found`.
   - `list_workflow_jobs`/`get_job_logs` returned zero jobs for that run.
   - Workaround: inspect `get_workflow_run` metadata (run URL, branch, event) and use the Actions UI/run page for details when API log endpoints are unavailable.

## High-value docs for deeper context
- `README.md` (project/release overview)
- `.github/workflows/README.md` (deployment/CI details)
- `.context/docs/testing-methodology.md`
- `.context/docs/integration-tests.md`
- `.context/docs/version-parsing.md`
- `.context/docs/v4-release-notes.md`
