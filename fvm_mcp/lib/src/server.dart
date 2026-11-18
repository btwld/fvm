import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:stream_channel/stream_channel.dart';

import 'arg_utils.dart';
import 'process_runner.dart';
import 'version.dart';

const String _serverName = 'fvm-mcp';
const String _serverVersion = String.fromEnvironment(
  'FVM_MCP_VERSION',
  defaultValue: '0.0.1-alpha.1',
);
final _readOnlyToolAnnotations = ToolAnnotations(
  readOnlyHint: true,
  destructiveHint: false,
  idempotentHint: true,
  openWorldHint: false,
);
final _mutatingToolAnnotations = ToolAnnotations(
  readOnlyHint: false,
  destructiveHint: true,
  idempotentHint: false,
  openWorldHint: false,
);
final _proxyToolAnnotations = ToolAnnotations(
  readOnlyHint: false,
  destructiveHint: true,
  idempotentHint: false,
  openWorldHint: true,
);

/// MCP server exposing FVM as tools.
/// Requires FVM on PATH. Tools are gated by detected version.
base class FvmMcpServer extends MCPServer with ToolsSupport {
  final FvmVersion fvm;
  final ProcessRunner _runner;

  FvmMcpServer._({
    required Implementation implementation,
    required StreamChannel<String> channel,
    required this.fvm,
    required ProcessRunner runner,
  }) : _runner = runner,
       super.fromStreamChannel(
         channel,
         implementation: implementation,
         instructions:
             'Use tools under the fvm.* namespace. Read-only JSON via fvm api; '
             'mutations are non-interactive where supported. '
             'Server v${implementation.version}. Detected FVM: ${fvm.raw}.',
       );

  /// Create, detect FVM version, then return a ready server.
  static Future<FvmMcpServer> start({
    required StreamChannel<String> channel,
  }) async {
    final detected = await detectFvmVersion();
    if (detected.isUnknown) {
      throw StateError(
        'Unable to detect FVM semver from `fvm --version`. '
        'Ensure FVM is on PATH and returns a semantic version.',
      );
    }

    final impl = Implementation(name: _serverName, version: _serverVersion);
    final server = FvmMcpServer._(
      implementation: impl,
      channel: channel,
      fvm: detected,
      runner: ProcessRunner(
        exe: resolveFvmExecutable(),
        hasSkipInput: detected.supportsSkipInput,
      ),
    );
    server._runner.bindNotifier(server.notifyProgress);

    return server.._registerTools();
  }

  // ---- Registration ----

  void _registerTools() {
    _registerJsonApiTools();
    _registerMutatingTools();
    _registerProxyTools();
  }

  void _registerJsonApiTools() {
    // JSON API (>= 3.1.2)
    if (fvm.supportsJsonApi) {
      _tool(
        name: 'fvm.api.list',
        desc: 'JSON: list cached Flutter SDKs',
        annotations: _readOnlyToolAnnotations,
        schema: ObjectSchema(
          properties: {
            'compress': BooleanSchema(
              description: 'Return minified JSON without formatting',
            ),
            'skip_size_calculation': BooleanSchema(
              description:
                  'Skip calculating SDK disk sizes for faster response',
            ),
          },
          additionalProperties: false,
        ),
        run: (call) => _runner.runJsonApi([
          'api',
          'list',
          ...flag(call, 'compress', '--compress'),
          ...flag(call, 'skip_size_calculation', '--skip-size-calculation'),
        ], meta: call.meta),
      );

      _tool(
        name: 'fvm.api.releases',
        desc: 'JSON: available Flutter releases',
        annotations: _readOnlyToolAnnotations,
        schema: ObjectSchema(
          properties: {
            'compress': BooleanSchema(
              description: 'Return minified JSON without formatting',
            ),
            'limit': IntegerSchema(minimum: 1),
            'filter_channel': StringSchema(
              description: 'Optional channel filter: stable|beta|dev',
              enumValues: ['stable', 'beta', 'dev'],
            ),
          },
          additionalProperties: false,
        ),
        run: (call) => _runner.runJsonApi([
          'api',
          'releases',
          ...opt(call, 'limit', (v) => ['--limit', '$v']),
          ...opt(call, 'filter_channel', (v) => ['--filter-channel', '$v']),
          ...flag(call, 'compress', '--compress'),
        ], meta: call.meta),
      );

      _tool(
        name: 'fvm.api.context',
        desc: 'JSON: FVM configuration, cache paths, and environment info',
        annotations: _readOnlyToolAnnotations,
        schema: ObjectSchema(
          properties: {
            'compress': BooleanSchema(
              description: 'Return minified JSON without formatting',
            ),
          },
          additionalProperties: false,
        ),
        run: (call) => _runner.runJsonApi([
          'api',
          'context',
          ...flag(call, 'compress', '--compress'),
        ], meta: call.meta),
      );

      _tool(
        name: 'fvm.api.project',
        desc: 'JSON: project config',
        annotations: _readOnlyToolAnnotations,
        schema: ObjectSchema(
          properties: {
            'path': StringSchema(description: 'Path to the Flutter project'),
            'compress': BooleanSchema(
              description: 'Return minified JSON without formatting',
            ),
          },
          additionalProperties: false,
        ),
        run: (call) => _runner.runJsonApi([
          'api',
          'project',
          ...opt(call, 'path', (v) => ['--path', '$v']),
          ...flag(call, 'compress', '--compress'),
        ], meta: call.meta),
      );
    }
  }

  void _registerMutatingTools() {
    // Mutating tools (require non-interactive support in FVM >= 3.2.0)
    if (fvm.supportsSkipInput) {
      _tool(
        name: 'fvm.install',
        desc: 'Install a Flutter SDK into cache (state-changing)',
        annotations: _mutatingToolAnnotations,
        schema: ObjectSchema(
          properties: {
            'version': StringSchema(),
            'setup': BooleanSchema(
              description:
                  'true -> --setup, false -> --no-setup (if supported)',
            ),
            'skip_pub_get': BooleanSchema(),
            'cwd': StringSchema(),
          },
          additionalProperties: false,
        ),
        run: (call) => _runner.run(
          [
            'install',
            ...maybeOne(call, 'version'),
            ...opt<bool>(call, 'setup', (s) => [s ? '--setup' : '--no-setup']),
            ...flag(call, 'skip_pub_get', '--skip-pub-get'),
          ],
          cwd: stringArg(call, 'cwd'),
          // installs can be long
          timeout: const Duration(minutes: 15),
          progressLabel: 'install',
          meta: call.meta,
        ),
      );

      _tool(
        name: 'fvm.remove',
        desc: 'Remove SDK(s) from cache (state-changing)',
        annotations: _mutatingToolAnnotations,
        schema: ObjectSchema(
          properties: {
            'version': StringSchema(),
            'all': BooleanSchema(),
            'cwd': StringSchema(),
          },
          additionalProperties: false,
        ),
        run: (call) {
          final all = boolArg(call, 'all') ?? false;
          final version = stringArg(call, 'version');
          if (all) {
            return _error(
              'fvm.remove with "all=true" is not supported in MCP '
              'non-interactive mode. Remove a specific version instead.',
            );
          }

          if (version == null) {
            return _error('Missing args: set "version".');
          }

          return _runner.run(
            ['remove', version],
            cwd: stringArg(call, 'cwd'),
            timeout: const Duration(minutes: 5),
            progressLabel: 'remove',
            meta: call.meta,
          );
        },
      );

      _tool(
        name: 'fvm.use',
        desc: 'Set SDK for current project (state-changing)',
        annotations: _mutatingToolAnnotations,
        schema: ObjectSchema(
          properties: {
            'version': StringSchema(),
            'force': BooleanSchema(),
            'pin': BooleanSchema(
              description:
                  'Pin to exact version, preventing automatic upgrades',
            ),
            'flavor': StringSchema(
              description: 'Named SDK configuration variant for the project',
            ),
            'env': StringSchema(
              description:
                  'Environment name for multi-environment project setups',
            ),
            'skip_setup': BooleanSchema(),
            'skip_pub_get': BooleanSchema(),
            'cwd': StringSchema(
              description: 'Working directory for the command',
            ),
          },
          additionalProperties: false,
        ),
        run: (call) => _runner.run(
          [
            'use',
            ...maybeOne(call, 'version'),
            ...flag(call, 'force', '--force'),
            ...flag(call, 'pin', '--pin'),
            ...opt(call, 'flavor', (v) => ['--flavor', '$v']),
            ...opt(call, 'env', (v) => ['--env', '$v']),
            ...flag(call, 'skip_setup', '--skip-setup'),
            ...flag(call, 'skip_pub_get', '--skip-pub-get'),
          ],
          cwd: stringArg(call, 'cwd'),
          timeout: const Duration(minutes: 10),
          progressLabel: 'use',
          meta: call.meta,
        ),
      );

      _tool(
        name: 'fvm.global',
        desc: 'Set/unlink global SDK (state-changing)',
        annotations: _mutatingToolAnnotations,
        schema: ObjectSchema(
          properties: {
            'version': StringSchema(),
            'force': BooleanSchema(),
            'unlink': BooleanSchema(),
          },
          additionalProperties: false,
        ),
        run: (call) {
          final unlink = boolArg(call, 'unlink') == true;
          final version = stringArg(call, 'version');
          final target = unlink ? '--unlink' : version;
          if (target == null) {
            return _error('Missing args: set "version" or "unlink=true".');
          }

          return _runner.run(
            ['global', target, ...flag(call, 'force', '--force')],
            timeout: const Duration(minutes: 2),
            progressLabel: 'global',
            meta: call.meta,
          );
        },
      );
    }
  }

  void _registerProxyTools() {
    // Proxies
    _tool(
      name: 'fvm.flutter',
      desc: 'Run flutter with the resolved project SDK',
      annotations: _proxyToolAnnotations,
      schema: ObjectSchema(
        properties: {
          'args': ListSchema(items: StringSchema()),
          'cwd': StringSchema(),
        },
        additionalProperties: false,
      ),
      run: (call) => _runner.run(
        ['flutter', ...listArg(call, 'args')],
        cwd: stringArg(call, 'cwd'),
        timeout: const Duration(minutes: 10),
        progressLabel: 'flutter',
        meta: call.meta,
      ),
    );

    _tool(
      name: 'fvm.dart',
      desc: 'Run dart with the resolved project SDK',
      annotations: _proxyToolAnnotations,
      schema: ObjectSchema(
        properties: {
          'args': ListSchema(items: StringSchema()),
          'cwd': StringSchema(),
        },
        additionalProperties: false,
      ),
      run: (call) => _runner.run(
        ['dart', ...listArg(call, 'args')],
        cwd: stringArg(call, 'cwd'),
        timeout: const Duration(minutes: 10),
        progressLabel: 'dart',
        meta: call.meta,
      ),
    );

    _tool(
      name: 'fvm.exec',
      desc: 'Execute a command under the project SDK environment',
      annotations: _proxyToolAnnotations,
      schema: ObjectSchema(
        required: ['command'],
        properties: {
          'command': StringSchema(minLength: 1),
          'args': ListSchema(items: StringSchema()),
          'cwd': StringSchema(),
        },
        additionalProperties: false,
      ),
      run: (call) {
        final command = stringArg(call, 'command');
        if (command == null) {
          return _error('Missing args: set non-empty "command".');
        }

        return _runner.run(
          ['exec', command, ...listArg(call, 'args')],
          cwd: stringArg(call, 'cwd'),
          timeout: const Duration(minutes: 10),
          progressLabel: 'exec',
          meta: call.meta,
        );
      },
    );

    _tool(
      name: 'fvm.spawn',
      desc: 'Run flutter <args> with a specific SDK version',
      annotations: _proxyToolAnnotations,
      schema: ObjectSchema(
        required: ['version'],
        properties: {
          'version': StringSchema(minLength: 1),
          'flutter_args': ListSchema(items: StringSchema()),
          'cwd': StringSchema(),
        },
        additionalProperties: false,
      ),
      run: (call) {
        final version = stringArg(call, 'version');
        if (version == null) {
          return _error('Missing args: set non-empty "version".');
        }

        return _runner.run(
          ['spawn', version, ...listArg(call, 'flutter_args')],
          cwd: stringArg(call, 'cwd'),
          timeout: const Duration(minutes: 10),
          progressLabel: 'spawn',
          meta: call.meta,
        );
      },
    );
  }

  // Tool registration helper.
  void _tool({
    required String name,
    required String desc,
    ToolAnnotations? annotations,
    required ObjectSchema schema,
    required Future<CallToolResult> Function(CallToolRequest call) run,
  }) {
    registerTool(
      Tool(
        name: name,
        description: desc,
        inputSchema: schema,
        annotations: annotations,
      ),
      (call) async {
        try {
          return await run(call);
        } on ArgumentError catch (e) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: e.toString())],
          );
        } on TypeError catch (e) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: 'Invalid arguments: $e')],
          );
        } catch (e, s) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: 'Unhandled error: $e\n$s')],
          );
        }
      },
    );
  }

  CallToolResult _error(String message) =>
      CallToolResult(isError: true, content: [TextContent(text: message)]);
}
