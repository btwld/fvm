## 4.3.3

* fix: publish the Chocolatey package with the prebuilt `fvm.exe` from the Windows release instead of compiling it on install, removing the exact `dart-sdk` dependency that blocked Dart SDK upgrades through Chocolatey (#1058, #1079)

## 4.3.2

* fix: preserve live command input/output, exit status, and Ctrl+C cleanup when falling back to the system PATH without a project or global SDK selection (#1080)
* chore: migrate FVM repository, release metadata fallback, and installer references to `btwld/fvm` (#1078)

## 4.3.1

* fix: wait for proxied Flutter commands to finish cleanup after Ctrl+C before FVM exits with status 130, preventing terminals from being left in raw mode (#1054)
* fix: support both `pub_updater` 0.4 and 0.5 in dependency resolution while retaining Dart 3.6 compatibility (#1022)

## 4.3.0

* feat: add `fvm cleanup` to preview unused cached SDKs and exact same-line stable patch upgrades, and to remove unused versions with `--remove-unused`. Recommended upgrade targets stay cached until a project or global pin moves; `fvm list` Unused now points here
* feat: add `fvm api cleanup` with `upgrades`, `unused`, and `removable`. `unused` matches `fvm list` Unused and `fvm api list` `unreferencedVersions`; `removable` is what `--remove-unused` would delete
* fix: explain when `fvm list` has no local project version to mark

## 4.2.0

* feat: add a `Projects` column to `fvm list` that shows how many known projects pin each cached SDK. Versions that no known project pins and that are not selected globally are labeled `Unused`. FVM records projects after `fvm use` or `fvm install` and reads their current `.fvmrc` values when listing
* feat: expose the project roots used for SDK classification and the resulting unused versions through `fvm api list` as `projects` and `unreferencedVersions`
* fix: correctly match forked channel pins such as `myfork/3.24.0@beta` to the installed `myfork/3.24.0` SDK in the `Local` and `Projects` columns

## 4.1.5

* perf: skip git-cache maintenance when running Flutter or Dart through an already-installed SDK (#1066)

## 4.1.4

* fix: stop git-cache maintenance from running destructive git commands against repositories FVM does not own (#1060)
* Behavior change: FVM now clears repository-scoped git environment variables (`GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, and the rest of the `git rev-parse --local-env-vars` set) when it runs `git`, `flutter`, or `dart`. Tools launched through FVM from inside a git hook, such as `fvm dart run` in a pre-commit hook, no longer see the hook's repository variables and will read the real index instead of the hook's staged index. Transport and auth variables like `GIT_SSH_COMMAND` and `GIT_ASKPASS` are preserved. (#1060)

## 4.1.2

* fix: stop rebuilding the git cache on every command when macOS leaves `.DS_Store` files in it (#1043)

## 4.1.1

* fix: prevent git cache bloat and stale SDK installs caused by outdated cache clones (#1037)
* fix: fall back to safe defaults instead of hanging when prompts run without an interactive terminal, like CI or git hooks (#1036)
* fix: stop false Flutter version-mismatch prompts when a project uses its own calendar-style git tags (#1033)

## 4.1.0

* feat: opt out of update checks for quieter CI and offline runs (#994)
* feat: keep working with cached SDKs even when Flutter drops the version file (#997)
* perf: faster installs and smaller disk usage with a leaner git cache (one-time repack on upgrade) (#1018)
* fix: stop forked versions from getting mixed up in the global cache (#995)
* fix: more reliable concurrent FVM commands (#1002)
* chore: cleanup cache handling and release parsing (#1005)

## 4.0.5

* feat: migrate install script to v2 with user-local default install (#967)
* fix: disable auto-install of shell completions for Nix/Home Manager environments (#991)
* fix: support legacy `.fvm/fvm_config.json` file loading (#996)
* fix: improve PATH guidance for CI installs (#999)

## 4.0.4

* fix: remove leading newline from fvm dart/flutter output
* fix: read or write cache with fork version by @huanghui1998hhh

## 4.0.3

* fix: preserve all project settings on fvm install

## 4.0.2

* fix: version detection for Flutter 3.38+ (version file removal)
* fix: filter hidden directories from cache version listing
* fix: route conflict in documentation site navigation
* docs: improve Android Studio/IntelliJ IDE configuration guide

## 4.0.1

* add: `fvm install` now runs setup by default
* add: RISC-V and 32-bit ARM architecture support
* add: SSH and scp-style git URL support for forks
* add: Standalone executables for host platform
* fix: `fvm doctor` crash when version not pinned
* fix: Alpine/musl libc detection in install script
* fix: Version prefix normalization in install script
* fix: Pre-push PATH hook auto-detects Flutter/Dart
* fix: Cache version matching logic
* fix: Uninstall script, git logging, and HTTP error handling
* fix: Code quality and analysis warnings
* docs: Git safe directory troubleshooting for Windows
* docs: PATH configuration for global version
* refactor: Migrate release tooling to dedicated package

## 4.0.0

* add: Manage Flutter SDKs from custom or forked repositories
* add: Automatic Melos integration - FVM automatically manages `sdkPath` in `melos.yaml`
* add: `updateMelosSettings` configuration option to control Melos integration per project
* fix: Enhanced environment variable processing logic
* fix: Better environment variable precedence handling

## 3.2.1

* fix: `--fvm-skip-input` flag not applying to context
* add: `fvm list` now displays the cache path even if no version is installed

## 3.2.0

* add: support for skipping input requests by @Rexios80. Input requests are skipped when the `--fvm-skip-input` flag is passed.
* add: documentation for command rerouting by @humblerookie
* fix(cosmetics): fvm has one newline too much by @jonasbadstuebner
* fix: unsupported architecture on arm64 by @MrCyjaneK
* add: tags for Docker deployment by @CodeRedDev
* add: Validate if git is installed by @leoafarias
* add: Disable local mirror on exception by @leoafarias

## 3.1.7

* Display the configured version in the `fvm list` command by @digoreis
* Handle progress printer exceptions by @leoafarias

## 3.1.6

* Improved messages when nested .fvmrc file is found.
* Better error handling for .git directory check.

## 3.1.5

* Improved mirror creation logging

## 3.1.4

* Disable git cache on CI environment by @leoafarias
* Add force flag to global command by @Rexios80
* Adds trailing space to version prompt by @pastrefvm/pull/705

## 3.1.3

* Fixed: Version weight handles custom versions properly by @quyenvsp
* Remove requirement for pubspec at the root for monorepos by @leoafarias

## 3.1.2

* Fixed: `fvm api context` command not been parsed correctly by @leoafarias

## 3.1.1

* Fixed: Empty flavors map been added to the project config by @leoafarias

## 3.1.0

* Initial release of [JSON API](https://fvm.app/documentation/advanced/json-api), allows for better integration of third-party tools and CI/CD workflows.

## 3.0.14

* Improvement: versioned brew formulae by @leoafarias
* Added: cli completion  by @leoafarias
* Improvement: Use posix path by @leoafarias
* Fixed: links in FAQ by @Pavel-Sulimau
* Fixed: forward configured flavors by @mrgnhnt96
* Added: destroy command by @leoafarias
* Added: install.sh scripts @leoafarias

## 3.0.13

* Added: `fvm use [version] --force` now skips install confirmation prompt by @mrgnhnt96
* Added: Added flag to skip pub get on `install` and `use`, `--skip-pub-get` by @mrgnhnt96
* Improvement: CI Flag now skips check update by @leoafarias
* Fix: Improve App Config and Project Config overrides by @leoafarias
* Fix: Incorrect check version update logic by @leoafarias
* Improvement: Better exception handling during mirror creation by @leoafarias
* Improvement: Added warning when .fvmrc is found but not pubspec.yaml by @leoafarias

## 3.0.12

* Adds skipping version mismatch handling when using force or running with a custom fvm version. [#653](https://github.com/btwld/fvm/issues/653)
* Fixes parsing error of vscode settings when there are commas [#656](https://github.com/btwld/fvm/issues/656)
* Sets global as first default if Dart SDK is not found in the project.

## 3.0.11

* Removed `fvm update` command. Due to issue with brew and chocolatey install.

## 3.0.10

* Fixed issue when config is found in directory no pubspec.yaml. [#638](https://github.com/btwld/fvm/issues/638)

## 3.0.9

* Adds .gitignore even if project is not a git repository. As IDEs and tools use it as a reference for project indexing.

## 3.0.8

* Implemented better validation checks for flavors [#639](https://github.com/btwld/fvm/issues/639)
* Added flag to unlink global version `fvm global --unlink` [#619](https://github.com/btwld/fvm/issues/619)

## 3.0.7

* `fvm use [version]` and `fvm install` now also create legacy `fvm_config.json` file for easier 3.0 migration path.
* However `fvm_config.json` is now deprecated in favor of `.fvmrc` file. FVM will migrate it automatically.

## 3.0.6

* `fvm flutter` command falls back to global fvm version if version not found in directory.

## 3.0.5

* Added fallback when cannot validate Flutter SDK version using git tags. [#627](https://github.com/btwld/fvm/issues/627)

## 3.0.4

* VsCode settings now supports jsonc (comments, trailing comma)
* Change flutter project check to only check for pubspec.yaml
* `fvm install`  command not creating sdk reference [#618](https://github.com/btwld/fvm/issues/618)

## 3.0.3

* Added check on update command for homebrew and chocolatey deployment.

## 3.0.2

* Removed validation for long commit hashes. FVM will now accept any length hash that git can return as a reference.

## 3.0.1

* Fixed Dart SDK download on brew installations.
* Do not ask for setup flow on VSCode if not detected.

## 3.0.0

### Added

* Tighter VSCode integration, with configuration and settings management. FVM will now automatically configure VSCode to use the correct Flutter SDK version, triggering a terminal path update, so you can just use `flutter` commands instead of `fvm flutter`
* Git Flutter repository mirroring for faster cloning of new versions.
* Added a check in .gitignore for the '.fvm' directory, and auto-adding it if necessary.
* Added verification if cached Flutter SDK has been upgraded, and provide options for corrective actions.
* Added a check for Flutter SDK constraints check for compatibility with current project.
* Improved FVM configuration management and settings.
* Ability to override FVM settings on a per project basis.
* Windows "unprivileged" mode. If you choose to run `fvm` in unprivileged mode, it will not require admin rights to run; however, local Flutter SDK project references will be absolute paths instead of relative links.

### Improvements

* Much improved DX with better error messages and logging, and more helpful information and how to proceed.
* Color output when using `fvm flutter` command proxy.
* Better SDK switching workflow per project. Handle more edge cases, by doing SDK comparisons.
* Better `fvm doctor` command. Now provides much better output and information about the project and environment.
* Better Dart SDK environment support, minimizes conflicts between multiple environment Dart SDKs.
* Improved `fvm releases` output.
* Improved `fvm list` output.
* Better error checking for `fvm global` command.
* FVM update check now runs only once a day.
* You can disable update check with the `--update-check` flag on `fvm config`

### Changed

* Command `fvm releases` now defaults to `stable` channel. Use `--all` flag to see all releases, or filter by channel.
* Removed "flavor" command in favor for `fvm use {flavor}`
* Removed "destroy" command in favor of `fvm remove --all`
* Config file is now `.fvmrc` instead of `.fvm/fvm_config.json`, and `.fvm` can be added to `.gitignore`, FVM will migrate it automatically.
* You can now use `fvm use {version} --env {flavor}` as an alias for `flavor`. Might be deprecated in the future since `env` has become a better description for environment specific settings than `flavor`.
* When installing or using a Flutter repo `commit hash`, hash needs to be 10 digits. FVM will now validate it and provide the correct hash if it can.

### Breaking Changes

* Default FVM config location is now `.fvmrc` instead of `.fvm/fvm_config.json`. FVM will migrate it automatically. However `.fvm` should be ignored, if you depend on `fvm_config.json` in your tools or CI, you should update your configuration.
* `fvm install` - Will not setup by default. Use `--setup` flag to setup Flutter SDK. Flag `--skip-setup` is removed.
* `fvm releases` - Defaults to `stable` releases. Use `--all` flag to see all releases, or filter by channel using `--channel {channel}`.
* `fvm flavor` - Removed in favor of `fvm use {flavor}`.
* `fvm use` - Will always setup by default. Use `--skip-setup` flag to skip setup.
* Environment variables `FVM_HOME` is now `FVM_CACHE_PATH`.
* Environment variables `FVM_GIT_CACHE` is now `FVM_FLUTTER_URL`.

## 2.4.1 - 2022-07-06

* Filter out Mac releases based on architecture.

## 2.4.0 - 2022-07-05

* Upgraded minimum Dart version to 2.17.0 for better Flutter 3.0 compatibility.

## 2.3.1 - 2022-04-07

* Updated Flutter releases endpoint.

## 2.3.0 - 2022-04-06

* Implemented `fvm exec` command. Execute terminal commands with the configured Flutter/Dart SDK version in the environment.
* `fvm use` command will install configured version by default if no version is provided.

## 2.2.6 - 2021-12-14

* Fixed an issue with routing to older Dart SDK directory path (before 1.17.5).

## 2.2.5 - 2021-12-09

* Clean `dart` command output `stdout` [Issue #361](https://github.com/btwld/fvm/issues/361).
* Better experience when running `dart pub cache repair` [Issue #352](https://github.com/btwld/fvm/issues/352).
* Dart proxy points to the correct path when version is older than 1.20.0 [Issue #348](https://github.com/btwld/fvm/issues/348).
* Flavors sequence of command causes `null` check exception [Issue #358](https://github.com/btwld/fvm/issues/358).

## 2.2.4 - 2021-11-09

* Ensures SDK is setup when running `use` command.

## 2.2.3 - 2021-08-31

* Fix archive URL from release info.

## 2.2.2 - 2021-06-18

* Small fix when checking for upgrade.

## 2.2.1 - 2021-06-18

* Fixed an edge case when running `flutter` command with `--no-version-check` flag.

## 2.2.0 - 2021-06-17

* Resolves channel unknown when pulling release version.
* Allows for release install of different channels [Read more](https://fvm.app/documentation).

## 2.1.1 - 2021-06-16

* Removed Flutter version validation check.
* Offline support.

## 2.1.0 - 2021-06-14

* Removed Windows permission check.

## 2.0.7 - 2021-06-14

* Updated Flutter releases URL.

## 2.0.6 - 2021-06-02

* Added a fallback if Flutter Release API is down.

## 2.0.5 - 2021-05-19

* Fixed concurrent Flutter commands execution on monorepos [Issue #296](https://github.com/btwld/fvm/issues/296).
* Added `cli_notify` to check for new version updates.

## 2.0.4 - 2021-05-06

* FVM only outputs information about version running when using `--verbose` flag [\#288](https://github.com/btwld/fvm/issues/288).

## 2.0.3 - 2021-05-04

* Fixed monorepo compatibility [Issue #285](https://github.com/btwld/fvm/issues/285).

## 2.0.2 - 2021-05-04

* Fixed a regression when running `fvm install` command.

## 2.0.1 - 2021-05-01

* Fix issue when retrieving settings [Issue #281](https://github.com/btwld/fvm/issues/281).

## 2.0.0 - 2021-05-01

* Feature: Environments - Set Flutter SDK versions per project environment.
* Feature: Doctor - Easily view the Flutter SDK version configuration for the project and the configuration state.
* Feature: Spawn - Easily proxy Flutter CLI commands through any cached version.
* Feature: Commits - Ability to install/use commits as the pinned Flutter SDK version.
* Feature: Custom versions - Manage custom Flutter SDK versions by adding `custom_` in front of the version.
* Improvements: null-safety.
* Improvements: Global - Create own command to set global versions. Deprecated `--global` flag.
* Improvements: Flutter command proxy now defaults to FVM global configured version before looking for one configured on `PATH`.
* Improvements: Better error messaging, notifications and logging.
* Improvements: Many quality of life (QoL) improvements.

## 1.3.8 - 2021-03-26

* Fixed an issue on FVM install [Issue #242](https://github.com/btwld/fvm/issues/242).
* Fixed an Auto linking issue [Issue #207](https://github.com/btwld/fvm/issues/207).

## 1.3.7 - 2020-12-18

* Fixed an issue for unwanted delay appearing after running `fvm use` command [\#195](https://github.com/btwld/fvm/issues/195).

## 1.3.6 - 2020-10-29

* Improvement: Added `PATH` env on Flutter processes for better third-party tooling support.
* Fix: Updated Grinder dependencies.
* Fix: Better ancestor lookup logic for monorepo setups. [Issue #180](https://github.com/btwld/fvm/issues/180).

## 1.3.5+1 - 2020-10-29

* Added symlink on install behavior without version.
* Clean-up.

## 1.3.4 - 2020-10-15

* Better support for CI and custom workflows using `fvm flutter ...` commands.

## 1.3.3 - 2020-10-14

* Fixed an error when setting up on some platforms and tools [Issue #160](https://github.com/btwld/fvm/issues/160).

## 1.3.2 - 2020-10-13

* Better logging for Flutter setup.

## 1.3.1 - 2020-10-11

* Fix issue when running `install` command with pinned version [Issue #161](https://github.com/btwld/fvm/issues/161).

## 1.3.0 - 2020-07-16

* Bug fixes and improvements.
* Implemented ability to change `cachePath` on settings [Issue #101](https://github.com/btwld/fvm/issues/101).
* Improved UX with `flutter run` command [Issue #124](https://github.com/btwld/fvm/issues/124).
* Added a notice on Windows to run in developer or administrator mode.
* Ability to set Flutter Git Repo URL (Advanced).

## 1.2.3 - 2020-08-22

* Clone setting changes. Unexpected behavior when installing master in some cases.

## 1.2.2 - 2020-08-19

* Updated process\_run dependency [(Issue #113)](https://github.com/btwld/fvm/pull/113).

## 1.2.0 - 2020-08-16

* `Use` command now shows the installed version if no 'version' is passed.
* Improved exception message handling.

## 1.1.9 - 2020-08-15

* Improvements on `flutter` channels parsing.

## 1.1.8 - 2020-08-14

* Fix for shared releases between channels.

## 1.1.7 - 2020-08-12

* Changed version on builder.

## 1.1.6 - 2020-08-12

* Better support for Windows.

## 1.1.5 - 2020-07-27

* Added a message with notice and fix if Flutter releases URL is blocked in your country.

## 1.1.4 - 2020-07-27

* Nested FVM config look up; to be used on monorepo projects or nested directories.
* Added a link to changelog on upgrade message.

## 1.1.3 - 2020-07-17

* Removed Flutter project guard from `flutter` proxy command.

## 1.1.2 - 2020-07-17

* Added upgrade message if not running the latest `fvm` version.

## 1.1.1 - 2020-07-17

* Static analysis and Dart convention notes added to README.md.

## 1.1.0 - 2020-07-16

* Implemented `--force` flag on `use` command to bypass guards if needed.
* Set where `fvm` caches versions using `FVM_HOME` environment variable.
* Deprecated `--cache-path` flag in favor of `FVM_HOME`.

## 1.0.4 - 2020-07-02

* Indicates global version on `list` command.

## 1.0.3 - 2020-07-02

* Fixed an issue with `stdin` on [Flutter CLI](https://docs.flutter.dev/reference/flutter-cli) commands.

## 1.0.2 - 2020-06-23

* Indicates channels on `fvm releases` command.

## 1.0.1 - 2020-06-22

* Suppress verbose message for install progress.

## 1.0.0 - 2020-06-22

* List Flutter Releases functionality.
* Bug fixes and optimizations.
* Project refactoring.

## 0.8.3 - 2020-06-20

* Installation progress output.
* Flutter setup on installation.
* Ability to skip setup with `--skip-setup` flag.

## 0.8.2 - 2020-06-19

* Size optimization of Flutter SDK downloads.
* Code clean-up.

## 0.8.1 - 2020-06-19

* Fixed `list` command when project has no config.

## 0.8.0 - 2020-06-18

* Implemented `--global` flag to set a specific version globally.
* Changed project configuration to allow for versioning.
* Refactoring and project clean-up.
* Better user experience.
* Improved error messages.

## 0.7.2 - 2020-06-18

* Better compatibility with [Flutter CLI](https://docs.flutter.dev/reference/flutter-cli) commands.

## 0.7.1 - 2020-06-18

* Updated `version` constant.

## 0.7.0 - 2020-04-14

* Added support for new Flutter 1.17.0+ [versioning scheme](https://groups.google.com/forum/#!msg/flutter-announce/b_EcYtyo8Q4/2QSfdp2aBwAJ) -
The new versioning scheme includes changes to tag names and thus also version names for FVM. When reinstalling Flutter versions <1.17.0, the FVM `install-path` will change, potentially breaking projects that rely on the `install-path`.
The `install-path` will change from `~/fvm/versions/1.15.17` to `~/fvm/versions/v1.15.17` (notice the letter `v` in the new version directory name). Make sure to change this in your IDE configuration.

## 0.6.7 - 2019-12-26

* Added `version` command to see currently installed `fvm` version.

## 0.6.6 - 2019-11-08

* Better [Flutter CLI](https://docs.flutter.dev/reference/flutter-cli) commands compatibility.
* Improved error logging and `--verbose` flag behavior.
* Friendlier error messages.

## 0.6.5 - 2019-11-08

* Better Error handling and friendlier error messages.

## 0.6.4 - 2019-11-08

* Project clean-up and tweaks for better `pub` analysis.

## 0.6.3 - 2019-11-07

* Initial stable version rewritten in Dart.
