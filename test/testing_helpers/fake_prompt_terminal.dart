import 'package:dart_console/dart_console.dart';
import 'package:fvm/src/utils/terminal_prompt.dart';
import 'package:tint/tint.dart';

/// [PromptTerminal] that replays scripted key presses and records output.
class FakePromptTerminal implements PromptTerminal {
  final List<Key> _keys;
  final StringBuffer _output = StringBuffer();

  @override
  final int? columns;

  /// Number of keys the prompt has read.
  var keysRead = 0;

  FakePromptTerminal(Iterable<Key> keys, {this.columns = 80})
      : _keys = keys.toList();

  /// Everything the prompt wrote, escape codes included.
  String get output => _output.toString();

  /// [output] without escape codes.
  String get plainOutput => output.strip();

  @override
  Key readKey() {
    if (keysRead >= _keys.length) {
      throw StateError('The prompt read more keys than the test provided.');
    }

    return _keys[keysRead++];
  }

  @override
  void write(String text) => _output.write(text);
}

/// Key presses for [FakePromptTerminal].
abstract final class Keys {
  static Key char(String char) => Key.printable(char);

  static Key get enter => Key.control(ControlCharacter.enter);

  static Key get lineFeed => Key.control(ControlCharacter.ctrlJ);

  static Key get escape => Key.control(ControlCharacter.escape);

  static Key get ctrlC => Key.control(ControlCharacter.ctrlC);

  static Key get up => Key.control(ControlCharacter.arrowUp);

  static Key get down => Key.control(ControlCharacter.arrowDown);

  static Key get tab => Key.control(ControlCharacter.tab);
}

/// Thrown by the fake `exit` passed to `Logger` in tests.
class FakeExit implements Exception {
  final int code;

  const FakeExit(this.code);

  @override
  String toString() => 'FakeExit($code)';
}

/// Fake `exit` for `Logger` that throws [FakeExit] instead of ending the VM.
Never fakeExit(int code) => throw FakeExit(code);
