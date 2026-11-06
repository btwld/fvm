import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/exceptions.dart';
import 'base_service.dart';

class ProcessService extends ContextualService {
  /// Environment variables that bind a git invocation to a specific
  /// repository (the set reported by `git rev-parse --local-env-vars`).
  ///
  /// These override git's repository discovery, and git hooks export some
  /// of them (linked-worktree hooks export an absolute `GIT_DIR`), so
  /// inheriting them would redirect FVM's git commands away from the
  /// directory they run in. Transport and authentication variables such
  /// as `GIT_SSH_COMMAND` and `GIT_ASKPASS` are preserved.
  static const _gitRepositoryScopedEnvVars = {
    'GIT_ALTERNATE_OBJECT_DIRECTORIES',
    'GIT_CONFIG',
    'GIT_CONFIG_PARAMETERS',
    'GIT_CONFIG_COUNT',
    'GIT_OBJECT_DIRECTORY',
    'GIT_DIR',
    'GIT_WORK_TREE',
    'GIT_IMPLICIT_WORK_TREE',
    'GIT_GRAFT_FILE',
    'GIT_INDEX_FILE',
    'GIT_NO_REPLACE_OBJECTS',
    'GIT_REPLACE_REF_BASE',
    'GIT_PREFIX',
    'GIT_SHALLOW_FILE',
    'GIT_COMMON_DIR',
  };

  const ProcessService(super.context);

  /// Whether [command] operates on git repositories FVM manages: git
  /// itself, and the Flutter/Dart SDK tools (which spawn their own git
  /// subprocesses). Commands with other names keep their environment.
  static bool _needsGitEnvScrubbing(String command) {
    final name = p.basenameWithoutExtension(command).toLowerCase();

    return name == 'git' || name == 'flutter' || name == 'dart';
  }

  Map<String, String> _scrubbedGitEnvironment(
    Map<String, String>? environment,
  ) {
    return {...context.environment, ...?environment}..removeWhere(
        (key, _) => _gitRepositoryScopedEnvVars.contains(key.toUpperCase()),
      );
  }

  void _throwIfProcessFailed(
    ProcessResult pr,
    String process,
    List<String> args,
  ) {
    if (pr.exitCode != 0) {
      final values = {
        if (pr.stdout != null) 'stdout': pr.stdout.toString().trim(),
        if (pr.stderr != null) 'stderr': pr.stderr.toString().trim(),
      }..removeWhere((k, v) => v.isEmpty);

      String message;
      if (values.isEmpty) {
        message = 'Unknown error';
      } else if (values.length == 1) {
        message = values.values.single;
      } else {
        if (values['stderr'] != null) {
          message = values['stderr']!;
        } else {
          message = values['stdout']!;
        }
      }

      throw ProcessException(process, args, message, pr.exitCode);
    }
  }

  Future<ProcessResult> run(
    String command, {
    List<String> args = const [],

    /// Listen for stdout and stderr
    String? workingDirectory,
    Map<String, String>? environment,
    bool throwOnError = true,
    bool echoOutput = false,
    bool runInShell = true,
  }) async {
    logger
      ..debug('')
      ..debug('Running: $command')
      ..debug('');
    final scrubGitEnv = _needsGitEnvScrubbing(command);
    final effectiveEnvironment =
        scrubGitEnv ? _scrubbedGitEnvironment(environment) : environment;
    ProcessResult processResult;
    if (!echoOutput || context.isTest) {
      processResult = await Process.run(
        command,
        args,
        workingDirectory: workingDirectory,
        environment: effectiveEnvironment,
        includeParentEnvironment: !scrubGitEnv,
        runInShell: runInShell,
      );

      if (throwOnError) {
        _throwIfProcessFailed(processResult, command, args);
      }

      return processResult;
    }
    StreamSubscription<ProcessSignal>? sigintSubscription;
    var interrupted = false;
    if (!Platform.isWindows && context.stdinHasTerminal) {
      sigintSubscription = ProcessSignal.sigint.watch().listen((_) {
        interrupted = true;
      });
    }

    // A terminal sends Ctrl+C to the whole foreground process group, but a
    // signal from another program, such as a test runner, IDE or CI timeout,
    // reaches only FVM. Forward it so that Flutter can clean up its child
    // processes instead of being orphaned when FVM exits.
    Process? child;
    ProcessSignal? forwardedSignal;
    final forwardSubscriptions = [
      if (!Platform.isWindows)
        for (final signal in [
          ProcessSignal.sigterm,
          ProcessSignal.sighup,
          if (!context.stdinHasTerminal) ProcessSignal.sigint,
        ])
          signal.watch().listen((received) {
            forwardedSignal ??= received;
            child?.kill(received);
          }),
    ];

    final Process process;
    final int processExitCode;
    try {
      process = await Process.start(
        command,
        args,
        workingDirectory: workingDirectory,
        environment: effectiveEnvironment,
        includeParentEnvironment: !scrubGitEnv,
        runInShell: runInShell,
        mode: ProcessStartMode.inheritStdio,
      );
      child = process;

      if (interrupted) {
        process.kill(ProcessSignal.sigint);
      }
      if (forwardedSignal case final signal?) {
        process.kill(signal);
      }
      processExitCode = await process.exitCode;
    } finally {
      await sigintSubscription?.cancel();
      for (final subscription in forwardSubscriptions) {
        await subscription.cancel();
      }
    }

    if (interrupted) {
      throw ForceExit('', 128 + ProcessSignal.sigint.signalNumber);
    }
    if (forwardedSignal case final signal?) {
      throw ForceExit('', 128 + signal.signalNumber);
    }

    processResult = ProcessResult(process.pid, processExitCode, null, null);
    if (throwOnError) {
      _throwIfProcessFailed(processResult, command, args);
    }

    return processResult;
  }
}

extension ProcessResultX on ProcessResult {
  // Note: `this.exitCode` is intentional -- without the explicit receiver,
  // Dart resolves to `dart:io`'s top-level `exitCode` getter.
  bool get isSuccess => this.exitCode == 0;

  bool get isFailure => this.exitCode != 0;
}
