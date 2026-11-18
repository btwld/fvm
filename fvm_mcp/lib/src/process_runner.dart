import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:process/process.dart';

class ProcessRunner {
  final String exe;
  final bool hasSkipInput;
  final ProcessStartMode startMode;
  final ProcessManager processManager;

  void Function(ProgressNotification notification)? _notify;

  ProcessRunner({
    required this.exe,
    required this.hasSkipInput,
    ProcessStartMode? startMode,
    ProcessManager? processManager,
  }) : startMode = startMode ?? ProcessStartMode.normal,
       processManager = processManager ?? const LocalProcessManager();

  String _formatCommand(List<String> args) {
    return [exe, ...args]
        .map((part) {
          final escaped = part.replaceAll('"', r'\"');

          return escaped.contains(' ') ? '"$escaped"' : escaped;
        })
        .join(' ');
  }

  Future<void> _drainStream(
    Stream<List<int>> stream,
    StringBuffer buffer,
  ) async {
    try {
      await stream.transform(utf8.decoder).forEach(buffer.write);
    } on Object {
      // Best-effort output collection should not fail the process result.
      buffer.write('');
    }
  }

  Future<CallToolResult> _runCore(
    List<String> args, {
    String? cwd,
    Duration timeout = const Duration(minutes: 2),
    String? progressLabel,
    MetaWithProgressToken? meta,
  }) async {
    final proc = await processManager.start(
      [exe, ...args],
      workingDirectory: cwd,
      mode: startMode,
    );

    final outBuf = StringBuffer();
    final errBuf = StringBuffer();

    final outDone = _drainStream(proc.stdout, outBuf);
    final errDone = _drainStream(proc.stderr, errBuf);

    if (meta?.progressToken != null && progressLabel != null) {
      _notify?.call(
        ProgressNotification(
          progressToken: meta!.progressToken!,
          progress: 0,
          total: 100,
          message: 'Starting $progressLabel…',
        ),
      );
    }

    int code;
    bool timedOut = false;
    try {
      code = await proc.exitCode.timeout(timeout);
    } on TimeoutException {
      timedOut = true;
      proc.kill(
        Platform.isWindows ? ProcessSignal.sigkill : ProcessSignal.sigterm,
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      proc.kill(ProcessSignal.sigkill);
      code = -1;
    } finally {
      // Let stdio drain after exit/kill; don't cancel streams early.
      try {
        if (timedOut) {
          await Future.wait([
            outDone,
            errDone,
          ]).timeout(const Duration(seconds: 2));
        } else {
          await Future.wait([outDone, errDone]);
        }
      } catch (_) {
        // Best-effort: if streams don't close, proceed with what we have.
      }
    }

    final stdoutText = outBuf.toString().trimRight();
    final stderrText = errBuf.toString().trimRight();

    if (meta?.progressToken != null && progressLabel != null) {
      _notify?.call(
        ProgressNotification(
          progressToken: meta!.progressToken!,
          progress: 100,
          total: 100,
          message: timedOut
              ? '$progressLabel timed out'
              : '$progressLabel done',
        ),
      );
    }

    final isContext =
        args.length >= 2 && args[0] == 'api' && args[1] == 'context';
    if (timedOut) {
      final message = StringBuffer()
        ..writeln('Timeout after ${timeout.inMinutes}m')
        ..writeln('Command: ${_formatCommand(args)}');
      if (!isContext && stderrText.isNotEmpty) {
        message.writeln(stderrText);
      }

      return CallToolResult(
        isError: true,
        content: [TextContent(text: message.toString().trimRight())],
      );
    }

    if (isContext) return _publicContext(code, stdoutText, args);

    if (code != 0) {
      final message = StringBuffer()
        ..writeln('Command: ${_formatCommand(args)}')
        ..writeln('Exit code: $code');
      if (stderrText.isNotEmpty) {
        message.writeln(stderrText);
      } else if (stdoutText.isNotEmpty) {
        message.writeln(stdoutText);
      }

      return CallToolResult(
        isError: true,
        content: [TextContent(text: message.toString().trimRight())],
      );
    }

    final text = stdoutText.isEmpty ? stderrText : stdoutText;

    return CallToolResult(content: [TextContent(text: text)]);
  }

  // Older FVM CLIs serialize the entire runtime context. Discard unknown
  // fields and raw diagnostics before returning any content to an MCP client.
  CallToolResult _publicContext(
    int code,
    String stdoutText,
    List<String> args,
  ) {
    try {
      final decoded = jsonDecode(stdoutText);
      final context = decoded is Map ? decoded['context'] : null;
      if (code == 0 && context is Map) {
        final visible = {
          for (final key in const [
            'fvmVersion',
            'fvmDir',
            'versionsCachePath',
            'gitCachePath',
            'globalCacheLink',
            'gitCache',
            'privilegedAccess',
          ])
            if (context[key] is String || context[key] is bool)
              key: context[key],
        };
        final encoder = args.contains('--compress')
            ? const JsonEncoder()
            : const JsonEncoder.withIndent('  ');
        return CallToolResult(
          content: [
            TextContent(text: encoder.convert({'context': visible})),
          ],
        );
      }
    } on FormatException {
      // Never include raw stdout or stderr for this command.
    }
    return CallToolResult(
      isError: true,
      content: [TextContent(text: 'Unable to read FVM context.')],
    );
  }

  void bindNotifier(void Function(ProgressNotification notification) notify) {
    _notify = notify;
  }

  Future<CallToolResult> runJsonApi(
    List<String> args, {
    String? cwd,
    Duration timeout = const Duration(minutes: 2),
    String? progressLabel,
    MetaWithProgressToken? meta,
  }) => _runCore(
    args,
    cwd: cwd,
    timeout: timeout,
    progressLabel: progressLabel,
    meta: meta,
  );

  Future<CallToolResult> run(
    List<String> args, {
    String? cwd,
    Duration timeout = const Duration(minutes: 2),
    String? progressLabel,
    MetaWithProgressToken? meta,
  }) {
    final full = [if (hasSkipInput) '--fvm-skip-input', ...args];

    return _runCore(
      full,
      cwd: cwd,
      timeout: timeout,
      progressLabel: progressLabel,
      meta: meta,
    );
  }
}
