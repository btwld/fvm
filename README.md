# fvm

[![Test CLI](https://img.shields.io/github/actions/workflow/status/btwld/fvm/test.yml?branch=main&label=Test%20CLI&style=for-the-badge&logo=GitHub)](https://github.com/btwld/fvm/actions/workflows/test.yml)
![GitHub stars](https://img.shields.io/github/stars/btwld/fvm?style=for-the-badge&logo=GitHub&logoColor=black&labelColor=white&color=dddddd)
[![Pub Version](https://img.shields.io/pub/v/fvm?label=version&style=for-the-badge&logo=dart&logoColor=3DB0F3&labelColor=white&color=3DB0F3)](https://pub.dev/packages/fvm/changelog)
[![Pub Likes](https://img.shields.io/pub/likes/fvm?style=for-the-badge&logo=dart&logoColor=3DB0F3&label=Pub%20Likes&labelColor=white&color=3DB0F3)](https://pub.dev/packages/fvm/score)
[![Pub Points](https://img.shields.io/pub/points/fvm?style=for-the-badge&logo=dart&logoColor=3DB0F3&label=Points&labelColor=white&color=3DB0F3)](https://pub.dev/packages/fvm/score)
[![All Contributors](https://img.shields.io/github/contributors/btwld/fvm?style=for-the-badge&color=018D5B&labelColor=004F32)](https://github.com/btwld/fvm/graphs/contributors)
[![MIT License](https://img.shields.io/github/license/btwld/fvm?style=for-the-badge&color=FF2E00&labelColor=CB2500)](https://github.com/btwld/fvm/blob/main/LICENSE)
[![Codecov](https://img.shields.io/codecov/c/github/btwld/fvm?style=for-the-badge&color=FFD43A&labelColor=F3BE00)](https://app.codecov.io/gh/btwld/fvm)
[![Awesome Flutter](https://img.shields.io/badge/awesome-flutter-8A00CB?style=for-the-badge&color=8A00CB&labelColor=630092)](https://github.com/Solido/awesome-flutter)

FVM manages Flutter SDK versions per project. Switch between Flutter versions instantly without reinstalling, making it easy to test new releases and maintain consistent builds across your team.

## Why FVM?

- Need for simultaneous use of multiple Flutter SDKs.
- SDK testing requires constant [channel](https://github.com/flutter/flutter/wiki/Flutter-build-release-channels) switching.
- Channel switches are slow and need repeated reinstalls.
- Difficulty managing the latest successful SDK version used in an app.
- Flutter's major updates demand total app migration.
- Inconsistencies occur in development environments within teams.

For more information, read the [Getting Started guide](https://fvm.app/documentation/getting-started).

## Release Process (For Maintainers)

FVM uses GitHub releases to trigger automated deployments across all platforms:

### Creating a New Release

1. **Ensure main branch is ready**
   - All changes merged and tested
   - Version will be set automatically from release tag

2. **Create GitHub Release**
   - Go to [GitHub Releases](https://github.com/btwld/fvm/releases)
   - Click "Create a new release"  
   - Choose tag: `v4.0.0-beta.2` (follows semver with 'v' prefix)
   - Write release notes in GitHub editor
   - Click "Publish release"

3. **Automated Deployment**
   - [`release.yml`](.github/workflows/release.yml) triggers automatically
   - Deploys to: pub.dev, GitHub binaries, Homebrew, Chocolatey, Docker
   - Monitor progress in [Actions tab](https://github.com/btwld/fvm/actions)

> **Dart SDK requirements:** Day-to-day development now targets the
> repository SDK constraint (`>=3.6.0 <4.0.0`). Release automation lives under
> `tool/release_tool/` and requires Dart SDK `>=3.8.0`. CI pins this higher tool
> chain via the `RELEASE_DART_SDK` environment variable (currently `3.9.0`) so
> it matches the versions packaged for Homebrew and other installers.
> If you run release tasks locally, switch to a Dart SDK `3.8.0` or newer
> before executing commands from `tool/release_tool/`.

### Emergency Releases

For hotfixes or emergency releases:
1. **Update version manually** in `pubspec.yaml`
2. **Use individual platform workflows** via manual dispatch:
   - `deploy_homebrew.yml` for Homebrew updates
   - `deploy_docker.yml` for Docker deployment
   - Individual platform deployments as needed

For complete emergency deployment, create a GitHub release as normal.

See [Workflow Documentation](.github/workflows/README.md) for detailed information.

## Contributors

<a href="https://github.com/btwld/fvm/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=btwld/fvm" />
</a>

---

Checkout Flutter Sidekick. [Read more about it here.](https://github.com/leoafarias/sidekick)

## Troubleshooting

Please view our [FAQ](https://fvm.app/documentation/getting-started/faq).

## License

This project is licensed under the MIT License; see [LICENSE](LICENSE) file for details.
