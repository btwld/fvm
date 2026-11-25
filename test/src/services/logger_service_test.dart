import 'dart:io';

import 'package:fvm/fvm.dart';
import 'package:fvm/src/services/logger_service.dart';
import 'package:mason_logger/mason_logger.dart' as mason;
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

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

/// `mason_logger` logger that records prompts and returns scripted answers.
class _FakeMasonLogger extends mason.Logger {
  final bool confirmAnswer;
  final int choiceIndex;

  String? confirmMessage;
  bool? confirmDefault;
  String? chooseMessage;
  List<Object?>? choices;
  Object? chooseDefault;
  var prompts = 0;

  _FakeMasonLogger({this.confirmAnswer = false, this.choiceIndex = 0});

  @override
  bool confirm(String? message, {bool defaultValue = false}) {
    prompts++;
    confirmMessage = message;
    confirmDefault = defaultValue;

    return confirmAnswer;
  }

  @override
  T chooseOne<T extends Object?>(
    String? message, {
    required List<T> choices,
    T? defaultValue,
    String Function(T choice)? display,
  }) {
    prompts++;
    chooseMessage = message;
    this.choices = choices;
    chooseDefault = defaultValue;

    return choices[choiceIndex];
  }
}

/// Stdout that reports whether a terminal is attached and discards output.
class _Stdout implements Stdout {
  @override
  final bool hasTerminal;

  _Stdout({required this.hasTerminal});

  @override
  bool get supportsAnsiEscapes => false;

  @override
  void write(Object? object) {}

  @override
  void writeln([Object? object = '']) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Runs [body] with stdout reporting [hasTerminal].
T _withStdout<T>(T Function() body, {required bool hasTerminal}) {
  return IOOverrides.runZoned(
    body,
    stdout: () => _Stdout(hasTerminal: hasTerminal),
  );
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
    Logger promptLogger(_FakeMasonLogger mason) {
      return Logger(
        TestFactory.context(stdinHasTerminal: true),
        masonLogger: mason,
      );
    }

    test('confirm asks mason_logger and returns its answer', () {
      for (final answer in [true, false]) {
        final mason = _FakeMasonLogger(confirmAnswer: answer);
        final logger = promptLogger(mason);

        final result = _withStdout(
          () => logger.confirm('Remove?', defaultValue: !answer),
          hasTerminal: true,
        );

        expect(result, answer);
        expect(mason.confirmMessage, 'Remove?');
        expect(mason.confirmDefault, !answer);
      }
    });

    test('select asks mason_logger and returns the chosen option', () {
      final mason = _FakeMasonLogger(choiceIndex: 1);
      final logger = promptLogger(mason);

      final result = _withStdout(
        () => logger.select('Pick', options: ['a', 'b', 'c']),
        hasTerminal: true,
      );

      expect(result, 'b');
      expect(mason.chooseMessage, 'Pick');
      expect(mason.choices, ['a', 'b', 'c']);
      expect(mason.chooseDefault, isNull);
    });

    test('select passes the default selection as the default option', () {
      final mason = _FakeMasonLogger(choiceIndex: 2);
      final logger = promptLogger(mason);

      final result = _withStdout(
        () => logger.select(
          'Pick',
          options: ['a', 'b', 'c'],
          defaultSelection: 2,
        ),
        hasTerminal: true,
      );

      expect(result, 'c');
      expect(mason.chooseDefault, 'c');
    });

    test('a null message is passed as an empty string', () {
      final mason = _FakeMasonLogger(confirmAnswer: true);
      final logger = promptLogger(mason);

      _withStdout(
        () {
          logger.confirm(null, defaultValue: false);
          logger.select(null, options: ['a']);
        },
        hasTerminal: true,
      );

      expect(mason.confirmMessage, '');
      expect(mason.chooseMessage, '');
    });

    test('prompts use their defaults when stdout is not a terminal', () {
      final mason = _FakeMasonLogger();
      final logger = promptLogger(mason);

      _withStdout(
        () {
          expect(logger.confirm('Remove?', defaultValue: true), isTrue);
          expect(
            logger.select('Pick', options: ['a', 'b'], defaultSelection: 1),
            'b',
          );
        },
        hasTerminal: false,
      );

      expect(mason.prompts, 0);
    });

    test('skipped input never asks mason_logger', () {
      final mason = _FakeMasonLogger();
      final logger = Logger(
        TestFactory.context(skipInput: true),
        masonLogger: mason,
      );

      _withStdout(
        () {
          expect(logger.confirm('Remove?', defaultValue: false), isFalse);
          expect(
            logger.select('Pick', options: ['a', 'b'], defaultSelection: 0),
            'a',
          );
        },
        hasTerminal: true,
      );

      expect(mason.prompts, 0);
    });
  });

  group('Interactive methods testing note', () {
    test('cacheVersionSelector interactive behavior', () {
      // Testing methods that rely on mason_logger prompts (and thus stdin) is challenging in unit tests.
      // One common approach is to refactor your Logger to inject a dependency for interactive input.
      // For example, you could pass in functions that simulate user responses.
      //
      // Alternatively, for unit tests you can set skipInput: true (and/or provide default selections)
      // so that the interactive branches (which call exit or block on input) are bypassed.
      //
      // Here, note that testing cacheVersionSelector without refactoring is not recommended,
      // because if skipInput is true and no defaultSelection is provided to select(),
      // the method calls exit() causing the test process to terminate.
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
