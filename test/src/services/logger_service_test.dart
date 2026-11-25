import 'package:fvm/fvm.dart';
import 'package:fvm/src/services/logger_service.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../testing_helpers/fake_prompt_terminal.dart';
import '../../testing_utils.dart';

class _SelectCaptureLogger extends Logger {
  _SelectCaptureLogger(super.context);

  List<String>? capturedOptions;
  int selectionIndex = 0;

  @override
  String select(
    String? message, {
    required List<String> options,
    int? defaultSelection,
  }) {
    capturedOptions = options;
    final index = selectionIndex < options.length ? selectionIndex : 0;
    return options[index];
  }
}

void main() {
  late Logger logger;

  setUp(() {
    logger = Logger(TestFactory.context());
  });
  group('Logger output tests', () {
    test('info adds message to outputs', () {
      logger.info("Test info message");
      expect(logger.outputs.contains("Test info message"), isTrue);
    });

    test('success logs with success icon', () {
      logger.success("Operation successful");
      final output = logger.outputs.join(' ');
      expect(output.contains('✓'), isTrue);
      expect(output.contains("Operation successful"), isTrue);
    });

    test('fail logs with failure icon', () {
      logger.fail("Operation failed");
      final output = logger.outputs.join(' ');
      expect(output.contains('✗'), isTrue);
      expect(output.contains("Operation failed"), isTrue);
    });

    test('warn adds message to outputs', () {
      logger.warn("Warning message");
      expect(logger.outputs.contains("Warning message"), isTrue);
    });

    test('err adds message to outputs', () {
      logger.err("Error message");
      expect(logger.outputs.contains("Error message"), isTrue);
    });

    test('detail adds message to outputs', () {
      logger.debug("Detail message");
      expect(logger.outputs.contains("Detail message"), isTrue);
    });

    test('write adds message to outputs', () {
      logger.write("Write message");
      expect(logger.outputs.contains("Write message"), isTrue);
    });

    test('confirm with skipInput true logs messages and returns default', () {
      final context = TestFactory.context(skipInput: true);
      final logger = Logger(context);

      final result = logger.confirm("Confirm prompt", defaultValue: false);
      expect(result, isFalse);
      // Verify that the confirmation prompt and warnings were added to outputs.
      expect(
        logger.outputs.any((msg) => msg.contains("Confirm prompt")),
        isTrue,
      );
      expect(
        logger.outputs.any(
          (msg) => msg.contains("Skipping input confirmation"),
        ),
        isTrue,
      );
      expect(
        logger.outputs.any(
          (msg) => msg.contains("Using default value of false"),
        ),
        isTrue,
      );
    });

    test('confirm with CI context logs messages and returns default', () {
      final context = TestFactory.context(
        environmentOverrides: const {'CI': 'true'},
      );
      final logger = Logger(context);

      final result = logger.confirm("Confirm prompt", defaultValue: true);

      expect(context.isCI, isTrue);
      expect(context.skipInput, isTrue);
      expect(result, isTrue);
      expect(
        logger.outputs.any(
          (msg) => msg.contains("Skipping input confirmation"),
        ),
        isTrue,
      );
      expect(
        logger.outputs.any(
          (msg) => msg.contains("Using default value of true"),
        ),
        isTrue,
      );
    });

    test(
      'select with skipInput true returns default selection when provided',
      () {
        final context = TestFactory.context(skipInput: true);
        final logger = Logger(context);
        // When skipInput is true and a defaultSelection is provided, the method returns the corresponding option.
        final result = logger.select(
          "Select an option",
          options: ['one', 'two'],
          defaultSelection: 1,
        );
        expect(result, equals('two'));
      },
    );

    test(
      'select with non-TTY stdin returns default selection when provided',
      () {
        final context = TestFactory.context(stdinHasTerminal: false);
        final logger = Logger(context);

        final result = logger.select(
          "Select an option",
          options: ['one', 'two'],
          defaultSelection: 1,
        );

        expect(context.stdinHasTerminal, isFalse);
        expect(context.skipInput, isTrue);
        expect(result, equals('two'));
      },
    );
  });

  group('Logger progress tests', () {
    test('progress logs message when verbose', () {
      final context = TestFactory.context(skipInput: true);
      final logger = Logger(context);
      // When verbose, progress cancels and logs the message.
      logger.progress("Processing...");
      expect(
        logger.outputs.any((msg) => msg.contains("Processing...")),
        isTrue,
      );
    });
  });

  group('Logger prompts', () {
    Logger promptLogger(FakePromptTerminal terminal) {
      return Logger(
        TestFactory.context(stdinHasTerminal: true),
        terminal: terminal,
        exitProcess: fakeExit,
      );
    }

    test('confirm returns the key the user pressed', () {
      expect(
        promptLogger(FakePromptTerminal([Keys.char('y')]))
            .confirm('Remove?', defaultValue: false),
        isTrue,
      );
      expect(
        promptLogger(FakePromptTerminal([Keys.char('n')]))
            .confirm('Remove?', defaultValue: true),
        isFalse,
      );
    });

    test('confirm returns the default on Enter', () {
      expect(
        promptLogger(FakePromptTerminal([Keys.enter]))
            .confirm('Remove?', defaultValue: true),
        isTrue,
      );
    });

    test('confirm answers no on Esc, even when the default is yes', () {
      final logger = promptLogger(FakePromptTerminal([Keys.escape]));

      expect(logger.confirm('Remove all?', defaultValue: true), isFalse);
    });

    test('confirm exits with 130 on Ctrl+C', () {
      final terminal = FakePromptTerminal([Keys.ctrlC]);
      final logger = promptLogger(terminal);

      expect(
        () => logger.confirm('Remove?', defaultValue: true),
        throwsA(isA<FakeExit>().having((e) => e.code, 'code', 130)),
      );
      expect(terminal.output, endsWith('\x1b[?25h'));
    });

    test('select returns the option the user picked', () {
      final logger = promptLogger(FakePromptTerminal([Keys.down, Keys.enter]));

      expect(logger.select('Pick', options: ['a', 'b', 'c']), 'b');
    });

    test('select starts on the default selection', () {
      final logger = promptLogger(FakePromptTerminal([Keys.enter]));

      expect(
        logger.select('Pick', options: ['a', 'b', 'c'], defaultSelection: 2),
        'c',
      );
    });

    test('select returns the default selection on Esc', () {
      final logger = promptLogger(
        FakePromptTerminal([Keys.down, Keys.escape]),
      );

      expect(
        logger.select('Pick', options: ['a', 'b', 'c'], defaultSelection: 2),
        'c',
      );
    });

    test('select exits with 64 on Esc when there is no default', () {
      final logger = promptLogger(FakePromptTerminal([Keys.escape]));

      expect(
        () => logger.select('Pick', options: ['a', 'b']),
        throwsA(isA<FakeExit>().having((e) => e.code, 'code', 64)),
      );
    });

    test('select exits with 130 on Ctrl+C', () {
      final terminal = FakePromptTerminal([Keys.ctrlC]);
      final logger = promptLogger(terminal);

      expect(
        () => logger.select('Pick', options: ['a', 'b'], defaultSelection: 0),
        throwsA(isA<FakeExit>().having((e) => e.code, 'code', 130)),
      );
      expect(terminal.output, endsWith('\x1b[?25h'));
    });

    test('skipped input never reads the terminal', () {
      final terminal = FakePromptTerminal([]);
      final logger = Logger(
        TestFactory.context(skipInput: true),
        terminal: terminal,
        exitProcess: fakeExit,
      );

      expect(logger.confirm('Remove?', defaultValue: true), isTrue);
      expect(
        logger.select('Pick', options: ['a', 'b'], defaultSelection: 1),
        'b',
      );
      expect(
        () => logger.select('Pick', options: ['a', 'b']),
        throwsA(isA<FakeExit>().having((e) => e.code, 'code', 64)),
      );
      expect(terminal.keysRead, 0);
      expect(terminal.output, isEmpty);
    });
  });

  group('Interactive methods testing note', () {
    test('cacheVersionSelector interactive behavior', () {
      // The interactive prompts are covered in the 'Logger prompts' group,
      // which passes a FakePromptTerminal and a fake exit to Logger. Without
      // them, select() with skipInput true and no defaultSelection would call
      // the real exit() and end the test process.
      expect(
        () => logger.cacheVersionSelector([]),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('cacheVersionSelector', () {
    test('includes fork aliases in options', () {
      final context = TestFactory.context();
      final logger = _SelectCaptureLogger(context);
      final forkDir = path.join(context.versionsCachePath, 'myfork', 'stable');
      final stableDir = path.join(context.versionsCachePath, 'stable');
      final versions = [
        CacheFlutterVersion.fromVersion(
          FlutterVersion.parse('myfork/stable'),
          directory: forkDir,
        ),
        CacheFlutterVersion.fromVersion(
          FlutterVersion.parse('stable'),
          directory: stableDir,
        ),
      ];

      final selected = logger.cacheVersionSelector(versions);

      expect(
        logger.capturedOptions,
        equals(versions.map((version) => version.nameWithAlias).toList()),
      );
      expect(selected, equals(versions.first.nameWithAlias));
    });

    test('returns selected option from select()', () {
      final context = TestFactory.context();
      final logger = _SelectCaptureLogger(context)..selectionIndex = 1;
      final versions = [
        CacheFlutterVersion.fromVersion(
          FlutterVersion.parse('stable'),
          directory: path.join(context.versionsCachePath, 'stable'),
        ),
        CacheFlutterVersion.fromVersion(
          FlutterVersion.parse('beta'),
          directory: path.join(context.versionsCachePath, 'beta'),
        ),
      ];

      final selected = logger.cacheVersionSelector(versions);

      expect(selected, equals(versions[1].nameWithAlias));
    });
  });
}
