import 'dart:convert';
import 'dart:io';

import 'package:fvm/src/models/config_model.dart';
import 'package:fvm/src/services/logger_service.dart';
import 'package:fvm/src/utils/constants.dart';
import 'package:fvm/src/utils/context.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _roleEnvironmentKey = 'FVM_LOGGER_PROMPT_PTY_ROLE';
const _scenarioEnvironmentKey = 'FVM_LOGGER_PROMPT_PTY_SCENARIO';
const _markerPrefix = 'FVM_PROMPT_TEST:';

const _enter = '0d';
const _escape = '1b';
const _ctrlC = '03';
const _arrowDown = '1b5b42';

String _requirePython3() {
  try {
    final result = Process.runSync('python3', const [
      '-c',
      'import pty, termios',
    ]);
    if (result.exitCode == 0) return 'python3';
  } on ProcessException {
    // Report the same focused prerequisite error as a failed module import.
  }

  fail(
    'python3 with the POSIX pty and termios modules is required to run '
    'the Logger prompt PTY test.',
  );
}

/// Runs [scenario] in a real terminal, presses [keys], and returns the report.
Future<Map<String, dynamic>> _runScenario(
  String scenario,
  List<String> keys,
) async {
  final repositoryRoot = Directory.current.path;
  // A CI marker would make FVM skip the prompt, so the harness never sees one.
  final environment = Map<String, String>.from(Platform.environment)
    ..removeWhere((key, _) => kCiEnvironmentVariables.contains(key));

  final result = await Process.run(
    _requirePython3(),
    [
      p.join(repositoryRoot, 'test', 'support_assets', 'logger_prompt_pty.py'),
      '--dart',
      Platform.resolvedExecutable,
      '--harness',
      p.join(
        repositoryRoot,
        'test',
        'src',
        'services',
        'logger_prompt_pty_test.dart',
      ),
      '--cwd',
      repositoryRoot,
      '--scenario',
      scenario,
      '--keys',
      keys.join(','),
    ],
    environment: environment,
    includeParentEnvironment: false,
    workingDirectory: repositoryRoot,
  );

  expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');

  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

// The test runner launches this file through a Python-owned PTY. The same file
// then acts as the FVM process that shows the prompt.
Future<void> main() async {
  if (Platform.environment[_roleEnvironmentKey] == 'prompt') {
    await _runPrompt(Platform.environment[_scenarioEnvironmentKey]!);
    return;
  }

  final skip = Platform.isWindows ? 'POSIX pseudo-terminal required' : false;
  const timeout = Timeout(Duration(minutes: 2));

  group('Logger prompts in a real terminal', () {
    test('confirm answers yes on y', () async {
      final report = await _runScenario('confirm', ['79']);

      expect(report['result'], 'true', reason: report['transcript']);
      expect(report['exitCode'], 0);
      expect(report['terminalRestored'], isTrue);
      expect(report['cursorShown'], isTrue);
    }, skip: skip, timeout: timeout);

    test('confirm answers no on a lone Esc', () async {
      final report = await _runScenario('confirm', [_escape]);

      expect(report['result'], 'false', reason: report['transcript']);
      expect(report['exitCode'], 0);
      expect(report['cursorShown'], isTrue);
    }, skip: skip, timeout: timeout);

    test('confirm exits with 130 and restores the terminal on Ctrl+C',
        () async {
      final report = await _runScenario('confirm', [_ctrlC]);

      expect(report['exitRequested'], 130, reason: report['transcript']);
      expect(report['exitCode'], 130);
      expect(report['terminalRestored'], isTrue);
      expect(report['cursorShown'], isTrue);
    }, skip: skip, timeout: timeout);

    test('select picks the option under the arrow', () async {
      final report = await _runScenario('select', [_arrowDown, _enter]);

      expect(report['result'], 'b', reason: report['transcript']);
      expect(report['exitCode'], 0);
      expect(report['cursorShown'], isTrue);
    }, skip: skip, timeout: timeout);

    test('select returns the default selection on Esc', () async {
      final report = await _runScenario('select-default', [_escape]);

      expect(report['result'], 'c', reason: report['transcript']);
      expect(report['exitCode'], 0);
    }, skip: skip, timeout: timeout);

    test('select exits with 64 on Esc when there is no default', () async {
      final report = await _runScenario('select', [_escape]);

      expect(report['exitRequested'], 64, reason: report['transcript']);
      expect(report['exitCode'], 64);
      expect(report['terminalRestored'], isTrue);
      expect(report['cursorShown'], isTrue);
    }, skip: skip, timeout: timeout);

    test('select exits with 130 and restores the terminal on Ctrl+C', () async {
      final report = await _runScenario('select', [_arrowDown, _ctrlC]);

      expect(report['exitRequested'], 130, reason: report['transcript']);
      expect(report['exitCode'], 130);
      expect(report['terminalRestored'], isTrue);
      expect(report['cursorShown'], isTrue);
    }, skip: skip, timeout: timeout);
  });
}

Future<void> _runPrompt(String scenario) async {
  final tempDirectory = Directory.systemTemp.createTempSync('fvm_prompt_pty_');

  try {
    final context = FvmContext.create(
      debugLabel: 'logger-prompt-pty',
      configOverrides: AppConfig(
        cachePath: p.join(tempDirectory.path, 'cache'),
        gitCachePath: p.join(tempDirectory.path, 'cache.git'),
        useGitCache: false,
        privilegedAccess: false,
        disableUpdateCheck: true,
      ),
      workingDirectoryOverride: Directory.current.path,
      appConfigPath: p.join(tempDirectory.path, 'config.json'),
      isTest: false,
    );
    if (context.skipInput) {
      stdout.writeln('${_markerPrefix}SKIP_INPUT');
      exitCode = 2;
      return;
    }

    final logger = Logger(
      context,
      exitProcess: (code) {
        stdout.writeln('${_markerPrefix}EXIT:$code');
        // Stay alive briefly so the driver can check the terminal mode.
        sleep(const Duration(milliseconds: 500));
        tempDirectory.deleteSync(recursive: true);
        exit(code);
      },
    );

    stdout.writeln('${_markerPrefix}READY');
    final result = switch (scenario) {
      'confirm' => logger.confirm('Remove?', defaultValue: true).toString(),
      'select' => logger.select('Pick', options: const ['a', 'b', 'c']),
      'select-default' => logger.select(
          'Pick',
          options: const ['a', 'b', 'c'],
          defaultSelection: 2,
        ),
      _ => throw ArgumentError.value(scenario, 'scenario'),
    };
    stdout.writeln('${_markerPrefix}RESULT:$result');
    await stdout.flush();
  } finally {
    if (tempDirectory.existsSync()) tempDirectory.deleteSync(recursive: true);
  }
}
