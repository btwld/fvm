import 'dart:io';

import 'package:dart_console/dart_console.dart';
import 'package:mason_logger/mason_logger.dart' as mason;
import 'package:stack_trace/stack_trace.dart';
import 'package:tint/tint.dart';

import '../models/cache_flutter_version_model.dart';
import '../models/log_level_model.dart';
import '../utils/exceptions.dart';
import 'base_service.dart';

mason.Level _toMasonLevel(Level level) {
  return mason.Level.values.firstWhere((e) => e.name == level.name);
}

Level _toLogLevel(mason.Level level) {
  return Level.values.firstWhere((e) => e.name == level.name);
}

class Logger extends ContextualService {
  final mason.Logger _logger;
  final bool _skipInput;
  final List<String> _outputs = [];

  /// [masonLogger] replaces the underlying `mason_logger` logger in tests.
  Logger(super.context, {mason.Logger? masonLogger})
      : _logger =
            masonLogger ?? mason.Logger(level: _toMasonLevel(context.logLevel)),
        _skipInput = context.skipInput;

  bool get isVerbose => level == Level.verbose;

  /// Whether prompts are skipped and resolved to their defaults.
  ///
  /// `mason_logger` prompts need a terminal on stdout as well as stdin.
  bool get _skipPrompts => _skipInput || !stdout.hasTerminal;

  Level get level => _toLogLevel(_logger.level);

  List<String> get outputs => _outputs;

  set level(Level level) => _logger.level = _toMasonLevel(level);

  void logTrace(StackTrace stackTrace) {
    final trace = Trace.from(stackTrace).toString();
    debug('');
    debug(trace);

    if (level != Level.verbose) {
      debug('');
      debug('Please run command with  --verbose if you want more information');
    }
  }

  void info([String message = '']) {
    _logger.info(message);
    _outputs.add(message);
  }

  void success(String message) {
    info('${Icons.success.green()} $message');
  }

  void fail(String message) {
    info('${Icons.failure.red()} $message');
  }

  void warn([String message = '']) {
    _logger.warn(message);
    _outputs.add(message);
  }

  void err([String message = '']) {
    _logger.err(message);
    _outputs.add(message);
  }

  void debug([String message = '']) {
    _logger.detail(message);
    _outputs.add(message);
  }

  void write(String message) {
    _logger.write(message);
    _outputs.add(message);
  }

  mason.Progress progress(String message) {
    final progress = _logger.progress(message);
    if (isVerbose) {
      // if verbose then cancel for other data been displayed and overlapping
      progress.cancel();
      // Replace for a normal log
      info(message);
    }

    return progress;
  }

  // Allows to select from cached sdks.
  String cacheVersionSelector(List<CacheFlutterVersion> versions) {
    // Return message if no cached versions
    if (versions.isEmpty) {
      throw const AppException(
        'No versions installed. Please install'
        ' a version. "fvm install {version}". ',
      );
    }

    /// Ask which version to select

    final versionsList =
        versions.map((version) => version.nameWithAlias).toList();

    final choice = select('Select a version: ', options: versionsList);

    return choice;
  }

  bool confirm(String? message, {required bool defaultValue}) {
    if (_skipPrompts) {
      info(message ?? '');
      warn('Skipping input confirmation');
      warn('Using default value of $defaultValue');

      return defaultValue;
    }

    return _logger.confirm(message ?? '', defaultValue: defaultValue);
  }

  String select(
    String? message, {
    required List<String> options,
    int? defaultSelection,
  }) {
    if (_skipPrompts) {
      if (defaultSelection != null) {
        return options[defaultSelection];
      }
      exit(mason.ExitCode.usage.code);
    }

    return _logger.chooseOne<String>(
      message ?? '',
      choices: options,
      defaultValue: defaultSelection == null ? null : options[defaultSelection],
    );
  }

  void notice(String message) {
    // Add 2 due to the warning icon.

    final label = '${Icons.warning} $message'.brightYellow();

    final table = Table()
      ..insertRow([label])
      ..borderColor = ConsoleColor.yellow
      ..borderType = BorderType.outline
      ..borderStyle = BorderStyle.square;

    write(table.toString());
  }

  void important(String message) {
    // Add 2 due to the warning icon.

    final label = '${Icons.success} $message'.cyan();

    final table = Table()
      ..insertRow([label])
      ..borderColor = ConsoleColor.cyan
      ..borderType = BorderType.outline
      ..borderStyle = BorderStyle.square;

    _logger.write(table.toString());
  }
}

class Icons {
  const Icons._();
  // Success: ✓
  static String get success => '✓';

  // Failure: ✗
  static String get failure => '✗';

  // Information: ℹ
  static String get info => 'ℹ';

  // Warning: ⚠
  static String get warning => '⚠';

  // Arrow Right: →
  static String get arrowRight => '→';

  // Arrow Left: ←
  static String get arrowLeft => '←';

  // Check Box: ☑
  static String get checkBox => '☑';

  // Star: ★
  static String get star => '★';

  // Circle: ●
  static String get circle => '●';

  // Square: ■
  static String get square => '■';
}
