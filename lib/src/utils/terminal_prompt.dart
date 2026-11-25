import 'dart:io';

import 'package:dart_console/dart_console.dart';
import 'package:tint/tint.dart';

/// Keyboard input and output for an interactive prompt.
///
/// [ConsoleTerminal] talks to the real terminal. Tests pass a fake.
abstract interface class PromptTerminal {
  /// Width of the terminal in columns, or null when it is unknown.
  int? get columns;

  /// Reads one key press, blocking until it arrives.
  Key readKey();

  /// Writes [text] to the terminal as is.
  void write(String text);
}

/// [PromptTerminal] backed by `dart_console`.
class ConsoleTerminal implements PromptTerminal {
  Console? _console;

  ConsoleTerminal();

  // Created on first use so non-interactive runs never touch the terminal.
  Console get _terminal => _console ??= Console();

  @override
  int? get columns => stdout.hasTerminal ? stdout.terminalColumns : null;

  @override
  Key readKey() => _terminal.readKey();

  @override
  void write(String text) => stdout.write(text);
}

/// Thrown when the user presses Ctrl+C in a prompt.
///
/// The prompt has already shown the cursor again and moved below its frame.
class PromptInterrupted implements Exception {
  const PromptInterrupted();

  @override
  String toString() => 'PromptInterrupted';
}

const _hideCursor = '\x1b[?25l';
const _showCursor = '\x1b[?25h';
const _clearToEnd = '\x1b[J';

final _inputPrefix = '? '.yellow();
final _inputSuffix = ' ›'.grey();
final _successPrefix = '✔ '.green();
final _cancelPrefix = '✘ '.red();
final _valueSeparator = ' ·'.grey();
final _activeItemPrefix = '❯'.green();

/// Asks a yes/no question in the terminal.
///
/// `y` or `n` answers at once and Enter takes [defaultValue]. Returns null
/// when the user presses Esc. Throws [PromptInterrupted] on Ctrl+C.
bool? promptConfirm(
  PromptTerminal terminal,
  String message, {
  required bool defaultValue,
}) {
  final question = message.trimRight();
  final header = '$_inputPrefix${question.bold()} ${'(y/n)'.grey()}'
      '$_inputSuffix ${_yesNo(defaultValue).cyan()}';

  return _PromptFrame(terminal).run((frame) {
    frame.draw([header]);

    while (true) {
      final key = frame.readKey();
      if (key.isControl) {
        switch (key.controlChar) {
          case ControlCharacter.enter || ControlCharacter.ctrlJ:
            return frame.answer(question, _yesNo(defaultValue), defaultValue);
          case ControlCharacter.escape:
            frame.cancel(question);

            return null;
          default:
            continue;
        }
      }

      switch (key.char) {
        case 'y' || 'Y':
          return frame.answer(question, _yesNo(true), true);
        case 'n' || 'N':
          return frame.answer(question, _yesNo(false), false);
      }
    }
  });
}

/// Asks the user to pick one of [options] in the terminal.
///
/// Arrow keys or `j` and `k` move through the list and wrap at both ends.
/// Enter picks the highlighted option. Returns its index, or null when the
/// user presses Esc. Throws [PromptInterrupted] on Ctrl+C.
int? promptSelect(
  PromptTerminal terminal,
  String message, {
  required List<String> options,
  int initialIndex = 0,
}) {
  if (options.isEmpty) {
    throw ArgumentError.value(options, 'options', 'must not be empty');
  }
  RangeError.checkValidIndex(initialIndex, options, 'initialIndex');

  final question = message.trimRight();
  final header = '$_inputPrefix${question.bold()}$_inputSuffix';
  var index = initialIndex;

  List<String> lines() => [
        header,
        for (var i = 0; i < options.length; i++)
          i == index
              ? '$_activeItemPrefix ${options[i].cyan()}'
              : '  ${options[i]}',
      ];

  return _PromptFrame(terminal).run((frame) {
    frame.draw(lines());

    while (true) {
      final key = frame.readKey();
      final control = key.isControl ? key.controlChar : null;

      if (control == ControlCharacter.enter ||
          control == ControlCharacter.ctrlJ) {
        return frame.answer(question, options[index], index);
      }
      if (control == ControlCharacter.escape) {
        frame.cancel(question);

        return null;
      }

      final up = control == ControlCharacter.arrowUp || key.char == 'k';
      final down = control == ControlCharacter.arrowDown || key.char == 'j';
      if (!up && !down) continue;

      index = (index + (up ? -1 : 1)) % options.length;
      frame.draw(lines());
    }
  });
}

String _yesNo(bool value) => value ? 'yes' : 'no';

/// Draws a prompt in place and keeps the terminal usable when it ends.
///
/// The frame is redrawn by moving the cursor up the rows it last used, so it
/// works anywhere on the screen, including the bottom row.
class _PromptFrame {
  final PromptTerminal _terminal;

  /// Rows the frame occupies. The cursor sits at the end of the last one.
  var _rows = 0;

  _PromptFrame(this._terminal);

  int _rowsFor(String line) {
    final columns = _terminal.columns;
    final width = line.strip().length;
    if (columns == null || columns <= 0 || width == 0) return 1;

    return (width + columns - 1) ~/ columns;
  }

  void _clear() {
    if (_rows == 0) return;
    final up = _rows - 1;
    _terminal.write('\r${up > 0 ? '\x1b[${up}A' : ''}$_clearToEnd');
    _rows = 0;
  }

  T run<T>(T Function(_PromptFrame frame) body) {
    _terminal.write(_hideCursor);
    try {
      return body(this);
    } finally {
      _terminal.write(_showCursor);
    }
  }

  Key readKey() {
    final key = _terminal.readKey();
    if (key.isControl && key.controlChar == ControlCharacter.ctrlC) {
      // Leave the frame on screen and start the next output on a fresh line.
      _terminal.write('\n');
      _rows = 0;
      throw const PromptInterrupted();
    }

    return key;
  }

  void draw(List<String> lines) {
    _clear();
    _terminal.write(lines.join('\n'));
    _rows = lines.fold(0, (total, line) => total + _rowsFor(line));
  }

  /// Collapses the frame to one line with the answer, then returns [result].
  T answer<T>(String question, String value, T result) {
    _clear();
    _terminal.write(
      '$_successPrefix${question.bold()}$_valueSeparator ${value.green()}\n',
    );

    return result;
  }

  /// Collapses the frame to one line that says it was cancelled.
  void cancel(String question) {
    _clear();
    _terminal.write(
      '$_cancelPrefix${question.bold()}$_valueSeparator ${'cancelled'.grey()}\n',
    );
  }
}
