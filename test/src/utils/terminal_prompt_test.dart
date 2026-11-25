import 'package:fvm/src/utils/terminal_prompt.dart';
import 'package:test/test.dart';

import '../../testing_helpers/fake_prompt_terminal.dart';

const _hideCursor = '\x1b[?25l';
const _showCursor = '\x1b[?25h';

void main() {
  group('promptConfirm', () {
    bool? confirm(FakePromptTerminal terminal, {bool defaultValue = false}) {
      return promptConfirm(terminal, 'Remove?', defaultValue: defaultValue);
    }

    test('y answers yes without Enter', () {
      final terminal = FakePromptTerminal([Keys.char('y')]);

      expect(confirm(terminal), isTrue);
      expect(terminal.keysRead, 1);
    });

    test('n answers no without Enter', () {
      final terminal = FakePromptTerminal([Keys.char('n')]);

      expect(confirm(terminal, defaultValue: true), isFalse);
    });

    test('uppercase Y and N are accepted', () {
      expect(confirm(FakePromptTerminal([Keys.char('Y')])), isTrue);
      expect(
        confirm(FakePromptTerminal([Keys.char('N')]), defaultValue: true),
        isFalse,
      );
    });

    test('Enter takes the default value', () {
      expect(
        confirm(FakePromptTerminal([Keys.enter]), defaultValue: true),
        isTrue,
      );
      expect(
        confirm(FakePromptTerminal([Keys.enter]), defaultValue: false),
        isFalse,
      );
    });

    test('a line feed counts as Enter', () {
      expect(
        confirm(FakePromptTerminal([Keys.lineFeed]), defaultValue: true),
        isTrue,
      );
    });

    test('Esc cancels and returns null, even when the default is yes', () {
      final terminal = FakePromptTerminal([Keys.escape]);

      expect(confirm(terminal, defaultValue: true), isNull);
      expect(terminal.plainOutput, contains('✘ Remove? · cancelled\n'));
    });

    test('other keys are ignored until an answer arrives', () {
      final terminal = FakePromptTerminal([
        Keys.char('x'),
        Keys.tab,
        Keys.up,
        Keys.char('y'),
      ]);

      expect(confirm(terminal), isTrue);
      expect(terminal.keysRead, 4);
    });

    test('shows the question with the default answer', () {
      final terminal = FakePromptTerminal([Keys.char('y')]);

      confirm(terminal, defaultValue: true);

      expect(terminal.plainOutput, contains('? Remove? (y/n) › yes'));
    });

    test('collapses to one line with the answer', () {
      final terminal = FakePromptTerminal([Keys.char('n')]);

      confirm(terminal, defaultValue: true);

      expect(terminal.plainOutput, endsWith('✔ Remove? · no\n'));
      expect(terminal.output, endsWith(_showCursor));
    });

    test('hides the cursor while asking and shows it again', () {
      final terminal = FakePromptTerminal([Keys.char('y')]);

      confirm(terminal);

      expect(terminal.output, startsWith(_hideCursor));
      expect(terminal.output, endsWith(_showCursor));
    });

    test('Ctrl+C throws PromptInterrupted after restoring the cursor', () {
      final terminal = FakePromptTerminal([Keys.ctrlC]);

      expect(() => confirm(terminal), throwsA(isA<PromptInterrupted>()));
      expect(terminal.output, endsWith('\n$_showCursor'));
    });
  });

  group('promptSelect', () {
    const options = ['stable', 'beta', '3.24.0'];

    int? select(FakePromptTerminal terminal, {int initialIndex = 0}) {
      return promptSelect(
        terminal,
        'Select a version:',
        options: options,
        initialIndex: initialIndex,
      );
    }

    test('Enter picks the highlighted option', () {
      expect(select(FakePromptTerminal([Keys.enter])), 0);
      expect(select(FakePromptTerminal([Keys.lineFeed])), 0);
    });

    test('starts on the initial index', () {
      expect(select(FakePromptTerminal([Keys.enter]), initialIndex: 2), 2);
    });

    test('arrow keys move the highlight', () {
      final terminal = FakePromptTerminal([
        Keys.down,
        Keys.down,
        Keys.up,
        Keys.enter,
      ]);

      expect(select(terminal), 1);
    });

    test('j and k move the highlight', () {
      final terminal = FakePromptTerminal([
        Keys.char('j'),
        Keys.char('j'),
        Keys.char('k'),
        Keys.enter,
      ]);

      expect(select(terminal), 1);
    });

    test('moving up from the first option wraps to the last', () {
      expect(select(FakePromptTerminal([Keys.up, Keys.enter])), 2);
    });

    test('moving down from the last option wraps to the first', () {
      expect(
        select(FakePromptTerminal([Keys.down, Keys.enter]), initialIndex: 2),
        0,
      );
    });

    test('Esc cancels and returns null', () {
      final terminal = FakePromptTerminal([Keys.down, Keys.escape]);

      expect(select(terminal), isNull);
      expect(
        terminal.plainOutput,
        contains('✘ Select a version: · cancelled\n'),
      );
    });

    test('other keys are ignored', () {
      final terminal = FakePromptTerminal([
        Keys.char('x'),
        Keys.tab,
        Keys.char(' '),
        Keys.enter,
      ]);

      expect(select(terminal), 0);
      expect(terminal.keysRead, 4);
    });

    test('draws the question and highlights the current option', () {
      final terminal = FakePromptTerminal([Keys.enter]);

      select(terminal, initialIndex: 1);

      expect(
        terminal.plainOutput,
        contains('? Select a version: ›\n  stable\n❯ beta\n  3.24.0'),
      );
    });

    test('redraws in place by moving up the rows it drew', () {
      final terminal = FakePromptTerminal([Keys.down, Keys.enter]);

      select(terminal);

      // Header plus three options is four rows, so the cursor moves up three
      // rows from the last one before clearing.
      expect(terminal.output, contains('\r\x1b[3A\x1b[J'));
      expect(terminal.output, isNot(contains('\x1b7')));
      expect(terminal.output, isNot(contains('\x1b8')));
    });

    test('counts rows that wrap in a narrow terminal', () {
      final terminal = FakePromptTerminal([Keys.down, Keys.enter], columns: 10);

      select(terminal);

      // The header '? Select a version: ›' is 21 columns, three rows at 10
      // columns, plus three option rows: six rows, so it moves up five.
      expect(terminal.output, contains('\r\x1b[5A\x1b[J'));
    });

    test('collapses to one line with the chosen option', () {
      final terminal = FakePromptTerminal([Keys.down, Keys.enter]);

      select(terminal);

      expect(terminal.plainOutput, endsWith('✔ Select a version: · beta\n'));
      expect(terminal.output, endsWith(_showCursor));
    });

    test('Ctrl+C throws PromptInterrupted after restoring the cursor', () {
      final terminal = FakePromptTerminal([Keys.down, Keys.ctrlC]);

      expect(() => select(terminal), throwsA(isA<PromptInterrupted>()));
      expect(terminal.output, startsWith(_hideCursor));
      expect(terminal.output, endsWith('\n$_showCursor'));
    });

    test('rejects an empty list and an out-of-range initial index', () {
      expect(
        () => promptSelect(FakePromptTerminal([]), 'Pick', options: const []),
        throwsArgumentError,
      );
      expect(
        () => promptSelect(
          FakePromptTerminal([]),
          'Pick',
          options: options,
          initialIndex: 3,
        ),
        throwsRangeError,
      );
    });
  });
}
