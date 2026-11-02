# FVM GitHub Workflows

## Hosted runner policy

GitHub Actions currently uses Linux runners only to limit compute usage.
macOS and Windows tests, deployments, Homebrew updates, and ARM64 smoke jobs
are paused. FVM MCP releases build Linux archives only. Restore the platform
jobs before promising new macOS or Windows release assets.

## Flutter release feeds

`data.yaml` refreshes the macOS, Windows, and Linux JSON release feeds hourly
at minute 17, or on manual dispatch. It validates all three responses before
changing files and commits changed feeds together. Semantically unchanged JSON
does not create a commit. The Python fetcher and its offline failure/no-change
tests live under `.github/scripts/`; Deno and the retired Flat action are no
longer required.

## Active Workflows

### `release.yml`
**Trigger**: Git tag push with `v*` pattern + manual dispatch
**Purpose**: Main deployment pipeline triggered by pushing a version tag
**Process**:
1. **Test** - Run all tests and quality checks
2. **Release** - Create GitHub release and deploy core packages:
   - 📦 pub.dev
   - 🐧 GitHub Linux binaries
   - Uses cli_pkg's `pkg-github-release` to create GitHub release from CHANGELOG
3. **Deploy** - Platform jobs are retained, with macOS and Windows paused:
   - 🍎 GitHub macOS binaries + Homebrew
   - 🪟 GitHub Windows binaries + Chocolatey
   - 🐳 Docker Hub

> Release Grinder tasks now live in `tool/release_tool` and require Dart SDK ≥ 3.8.
> Run release commands from that directory (e.g. `cd tool/release_tool && dart pub get && dart run grinder pkg-github-release`).
> CI pins this toolchain via the `RELEASE_DART_SDK` environment variable (currently `3.9.0`,
> aligned with our Homebrew formula) while the rest of the repo targets the
> lower (`>=3.6.0`) constraint for everyday development.

**Usage**:
1. Update `pubspec.yaml` version
2. Update `CHANGELOG.md` with release notes
3. Run `dart run build_runner build` to generate version.dart
4. Commit changes
5. Tag with `v` prefix: `git tag v4.0.0-beta.3`
6. Push tag: `git push origin v4.0.0-beta.3`
7. Linux and Docker deployment run automatically; macOS and Windows are paused.

### `release-fvm-mcp.yml`
**Trigger**: Git tag push with `fvm-mcp-v*` pattern + manual dispatch  
**Purpose**: Build and publish `fvm_mcp` standalone binaries to GitHub Releases
**Process**:
1. **Validate** - Enforce release tag format and version consistency:
   - Tag must match `fvm-mcp-v<semver>`
   - Tag version must match `fvm_mcp/pubspec.yaml`
   - Tag version must match `fvm_mcp/lib/src/server.dart` default server version
2. **Build** - Compile Linux binaries; the other runner entries are paused:
   - 🐧 Linux (`tar.gz`)
   - 🍎 macOS (`tar.gz`)
   - 🪟 Windows (`zip`)
3. **Publish** - Create/update GitHub release and upload:
   - Platform archives
   - `SHA256SUMS` integrity file

**Usage**:
1. Update `fvm_mcp/pubspec.yaml` version
2. Update `fvm_mcp/lib/src/server.dart` `FVM_MCP_VERSION` default
3. Add/update `fvm_mcp/CHANGELOG.md` entry for that exact version
4. Commit changes
5. Tag with MCP prefix: `git tag fvm-mcp-v0.0.1-alpha.1`
6. Push tag: `git push origin fvm-mcp-v0.0.1-alpha.1`
7. `release-fvm-mcp.yml` publishes release assets automatically

### `test.yml`
**Trigger**: Push, PR, workflow_call  
**Purpose**: Run all tests and quality checks  
**Used by**: Other workflows for validation before deployment

### `test-install.yml` 
**Trigger**: Manual dispatch  
**Purpose**: Test FVM installation across different platforms

## Standalone Deploy Workflows

### Platform-Specific Deploy Workflows
- `deploy_docker.yml` - Standalone Docker deployment
- `deploy_homebrew.yml` - Standalone Homebrew updates  
- `deploy_macos.yml` - Standalone macOS deployment
- `deploy_windows.yml` - Standalone Windows deployment

## Recommended Release Process

### 🚀 Standard Release (Recommended)

1. **Prepare Release**
   - Update `pubspec.yaml` with new version number
   - Update `CHANGELOG.md` with release notes (use traditional format with bullet points)
   - Run `dart run build_runner build --delete-conflicting-outputs` to generate `lib/src/version.dart`
   - Commit all changes: `git commit -m "chore: prepare vX.Y.Z release"`

2. **Create and Push Tag**
   - Create tag: `git tag vX.Y.Z` (e.g., `v4.0.0-beta.3`)
   - Push tag: `git push origin vX.Y.Z`

3. **Automatic Deployment**
   - `release.yml` triggers automatically on tag push
   - cli_pkg creates GitHub release from CHANGELOG content
   - Monitor progress in [Actions](https://github.com/btwld/fvm/actions)
   - Linux and Docker deploy; macOS and Windows deployments are paused

### 🧩 FVM MCP Release (Standalone)

1. **Prepare MCP version**
   - Update `fvm_mcp/pubspec.yaml` version (for example `0.0.1-alpha.1`)
   - Update `fvm_mcp/lib/src/server.dart` default `FVM_MCP_VERSION`
   - Add a matching section in `fvm_mcp/CHANGELOG.md`
   - Commit changes

2. **Create and Push MCP Tag**
   - Create tag: `git tag fvm-mcp-vX.Y.Z` or `git tag fvm-mcp-vX.Y.Z-alpha.N`
   - Push tag: `git push origin fvm-mcp-vX.Y.Z`

3. **Automatic MCP Deployment**
   - `release-fvm-mcp.yml` validates version alignment
   - Builds Linux standalone binaries; macOS and Windows are paused
   - Publishes assets and checksums to the tagged GitHub release

### ⚡ Emergency Release (Alternative)

For hotfixes or platform-specific urgent updates, use individual platform workflows:

- Manual dispatch `deploy_homebrew.yml` for Homebrew-only updates
- Manual dispatch `deploy_docker.yml` for Docker-only updates
- Manual dispatch individual platform workflows as needed

## Version Management

- **Version Source**: `pubspec.yaml` (manually updated before tagging)
- **Tag Format (FVM CLI)**: Must follow semver with `v` prefix: `v4.0.0-beta.2`
- **Tag Format (FVM MCP)**: Must follow semver with `fvm-mcp-v` prefix: `fvm-mcp-v0.0.1-alpha.1`
- **CHANGELOG**: cli_pkg reads CHANGELOG.md to populate GitHub release notes
- **Generated Files**: `lib/src/version.dart` is generated by build_runner from pubspec.yaml

## Troubleshooting

### Workflow doesn't trigger
- Ensure tag is pushed to remote (not just created locally)
- Check that tag follows the correct pattern for the workflow:
  - `v*` for `release.yml`
  - `fvm-mcp-v*` for `release-fvm-mcp.yml`
- Verify all required secrets are configured

### Binary upload fails
- Check if GitHub release exists with matching tag
- Verify `GITHUB_TOKEN` has release permissions
- Ensure standalone binaries built successfully

### Platform deployment fails
- Check platform-specific tokens (Chocolatey, Homebrew, Docker)
- Verify runner OS matches deployment target
- Review build logs for specific error details



### Integration scope

`Test CLI` keeps root, MCP and release-tool unit tests on every triggered run.
Only PRs changing exclusively `fvm_mcp/`, `tool/release_tool/` and optional
root Markdown skip the SDK-download integration and v3 migration jobs. This
uses the verified PR merge diff rather than a branch-name exception. Any CLI,
dependency, shared fixture, tooling, workflow or unknown path runs both heavy
suites. Main/develop pushes, manual and reusable workflow calls always run
them; missing or uncertain Git history also requests the full suites.
