import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:fvm_mcp/src/process_runner.dart';
import 'package:test/test.dart';

void main() {
  const script = 'test/bin/fake_fvm.dart';
  late final String fakeFvmExe;

  Future<String> _compileFakeFvm() async {
    final tmp = await Directory.systemTemp.createTemp('fvm_mcp_fake_fvm_');
    addTearDown(() async {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    });
    final outName = Platform.isWindows ? 'fake_fvm.exe' : 'fake_fvm';
    final outPath = '${tmp.path}/$outName';

    final result = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      script,
      '-o',
      outPath,
    ], runInShell: Platform.isWindows);
    if (result.exitCode != 0) {
      throw StateError(
        'Failed to compile fake_fvm:\n${result.stdout}\n${result.stderr}',
      );
    }
    return outPath;
  }

  ProcessRunner runner({required bool hasSkipInput}) => ProcessRunner(
    exe: fakeFvmExe,
    hasSkipInput: hasSkipInput,
    startMode: ProcessStartMode.normal,
  );

  String textFrom(CallToolResult result) {
    final contents = result.content.whereType<TextContent>();
    return contents.map((c) => c.text).join('\n');
  }

  setUpAll(() async {
    fakeFvmExe = await _compileFakeFvm();
  });

  test('context from an older CLI exposes public fields only', () async {
    final result = await runner(
      hasSkipInput: false,
    ).runJsonApi(['api', 'context']);
    expect(jsonDecode(textFrom(result)), {
      'context': {'fvmVersion': '3.1.2'},
    });
  });

  test('run returns stdout text', () async {
    final res = await runner(
      hasSkipInput: false,
    ).run(['echo', 'hello', 'world']);

    expect(res.isError, anyOf(isNull, isFalse));
    expect(textFrom(res), 'hello world');
  });

  test('run passes --fvm-skip-input when supported', () async {
    final res = await runner(
      hasSkipInput: true,
    ).run(['echo_args_json', 'alpha']);

    expect(res.isError, anyOf(isNull, isFalse));
    final decoded = jsonDecode(textFrom(res)) as Map<String, dynamic>;
    expect(decoded['hadSkipInput'], isTrue);
    expect(decoded['args'], equals(['alpha']));
  });

  test('non-zero exit surfaces stderr', () async {
    final res = await runner(hasSkipInput: false).run(['stderr', 'boom']);

    expect(res.isError, isTrue);
    expect(textFrom(res), contains('Command:'));
    expect(textFrom(res), contains('Exit code: 1'));
    expect(textFrom(res), contains('boom'));
  });

  test('non-zero exit without output includes exit code', () async {
    final res = await runner(hasSkipInput: false).run(['exit', '7']);

    expect(res.isError, isTrue);
    final text = textFrom(res);
    expect(text, contains('Command:'));
    expect(text, contains('Exit code: 7'));
  });

  test('timeout produces structured error', () async {
    final res = await runner(hasSkipInput: false).run(
      ['sleep', '2'],
      timeout: const Duration(milliseconds: 100),
      progressLabel: 'sleep',
    );

    expect(res.isError, isTrue);
    final text = textFrom(res);
    expect(text, contains('Command:'));
    expect(text, contains('Timeout after 0m'));
  });
}
