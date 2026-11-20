# fvm_mcp

MCP server that mirrors the FVM CLI as tools (stdio transport). The context endpoint returns public FVM settings and cache paths; writes are non-interactive on FVM ≥ 3.2.
Current release status: **alpha** (`0.0.1-alpha.1`).

## Prerequisites

- Install FVM on `PATH`. On Windows, the MCP server requires a native `fvm.exe` in an absolute `PATH` directory.
- For source execution: Dart SDK `>=3.9.0 <4.0.0`.

## Run From Source

```bash
cd fvm_mcp
dart pub get
dart run bin/fvm_mcp.dart
```

MCP client config (source mode):

```json
{
  "command": "dart",
  "args": ["run", "bin/fvm_mcp.dart"],
  "cwd": "/absolute/path/to/repo/fvm_mcp"
}
```

## Install Standalone Binary

`fvm_mcp` releases publish prebuilt binaries on GitHub for Linux, macOS, and Windows.

- Download the archive for your platform from the tagged release:
  - `fvm_mcp-<version>-linux-x64.tar.gz`
  - `fvm_mcp-<version>-macos.tar.gz`
  - `fvm_mcp-<version>-windows-x64.zip`
- Extract the binary.
- Add it to your `PATH`.
- Configure your MCP client to launch it over stdio.

MCP client config (binary mode):

```json
{
  "command": "fvm_mcp",
  "args": []
}
```

### Tools

- Read-only JSON: `fvm.api.list`, `fvm.api.releases`, `fvm.api.context`, `fvm.api.project`.
- Mutating (FVM ≥ 3.2.0): `fvm.install`, `fvm.remove`, `fvm.use`, `fvm.global`.
- Proxies: `fvm.flutter`, `fvm.dart`, `fvm.exec`, `fvm.spawn`.

JSON API flags and response fields follow the FVM docs. Command flags and routing order follow the FVM commands reference.

### Version Gates

- JSON API available since 3.1.0; api context fix in 3.1.2 → gate at ≥ 3.1.2.
- Mutating tools require non-interactive support via `--fvm-skip-input` (≥ 3.2.0).

### Embed into FVM (`fvm mcp`)

Add a subcommand to the FVM CLI that constructs a stdio channel and calls `FvmMcpServer.start(...)`. This keeps the MCP surface version-locked to the installed FVM.

```dart
// lib/src/commands/mcp_command.dart  (inside FVM CLI)
import 'dart:io';
import 'package:dart_mcp/stdio.dart';
import 'package:fvm_mcp/src/server.dart';
import 'package:args/command_runner.dart';

class McpCommand extends Command<int> {
  @override
  final name = 'mcp';
  @override
  final description = 'Start the embedded MCP server over stdio.';

  @override
  Future<int> run() async {
    final channel = stdioChannel(input: stdin, output: stdout);
    final server = await FvmMcpServer.start(channel: channel);
    await server.done;
    return 0;
  }
}

// In the CLI entry, add:  runner.addCommand(McpCommand());
```

## Deployment Plan

- Source of truth for version:
  - `fvm_mcp/pubspec.yaml`
  - `fvm_mcp/lib/src/server.dart` (`FVM_MCP_VERSION` default)
- Release notes source:
  - `fvm_mcp/CHANGELOG.md` section matching the tagged version
- Release tag format:
  - `fvm-mcp-v<semver>` (example: `fvm-mcp-v0.0.1-alpha.1`)
- CI/CD workflow:
  - `.github/workflows/release-fvm-mcp.yml`
- Release outputs:
  - Platform archives (Linux/macOS/Windows)
  - `SHA256SUMS` checksum file
- Consumer install path:
  - Download binary archive from GitHub release
  - Extract binary and place on `PATH`
  - Point MCP client at binary command

## Automated Deployment

`release-fvm-mcp.yml` is fully automated:

- Triggered by pushing tags that match `fvm-mcp-v*`.
- Validates tag/version alignment against package and runtime server version.
- Validates that `fvm_mcp/CHANGELOG.md` contains a section for the tagged version.
- Builds binaries on GitHub-hosted runners.
- Publishes release assets and checksums to GitHub Releases.

### Safety

- Mutating tools are marked “state-changing”.
- `remove` supports specific `version` removal only.
- Proxies honor FVM’s routing order (project → ancestor → global → PATH).

## License

MIT
