import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fvm/src/models/config_model.dart';
import 'package:fvm/src/services/process_service.dart';
import 'package:fvm/src/utils/context.dart';
import 'package:fvm/src/utils/exceptions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _roleEnvironmentKey = 'FVM_PROCESS_SERVICE_SIGNAL_ROLE';
const _parentRole = 'parent';
const _childRole = 'child';
const _markerPrefix = 'FVM_SIGNAL_TEST:';

// The test starts this file as an FVM parent without a terminal, the way a
// test runner or IDE starts `fvm flutter`. The parent starts the same file as
// a signal-aware child, which stands in for the Flutter tool.
Future<void> main() async {
  final role = Platform.environment[_roleEnvironmentKey];
  if (role == _parentRole) {
    await _runParent();
    return;
  }
  if (role == _childRole) {
    await _runChild();
    return;
  }

  for (final signal in [ProcessSignal.sigterm, ProcessSignal.sighup]) {
    test(
      'forwards $signal to the child and waits for its cleanup',
      () async {
        final parent = await Process.start(
          Platform.resolvedExecutable,
          [
            p.join(
              Directory.current.path,
              'test',
              'src',
              'services',
              'process_service_signal_forwarding_test.dart',
            ),
          ],
          environment: {
            ...Platform.environment,
            _roleEnvironmentKey: _parentRole,
          },
        );
        final markers = <String>[];
        final childReady = Completer<int>();
        final stdoutDone = parent.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .where((line) => line.startsWith(_markerPrefix))
            .map((line) => line.substring(_markerPrefix.length))
            .forEach((marker) {
          markers.add(marker);
          if (marker.startsWith('CHILD_READY:')) {
            childReady.complete(int.parse(marker.split(':').last));
          }
        });

        final childPid = await childReady.future;
        // Without forwarding, the orphaned child would outlive the test.
        addTearDown(() => Process.killPid(childPid, ProcessSignal.sigkill));
        parent.kill(signal);
        final parentExitCode = await parent.exitCode;
        await stdoutDone.timeout(const Duration(seconds: 10), onTimeout: () {});

        expect(markers, [
          'CHILD_READY:$childPid',
          'CHILD_SIGNAL:$signal',
          'CHILD_CLEANUP_DONE',
          'PARENT_FORCE_EXIT:${128 + signal.signalNumber}',
        ]);
        expect(parentExitCode, 128 + signal.signalNumber);
        expect(Process.killPid(childPid, ProcessSignal.sigcont), isFalse);
      },
      skip: Platform.isWindows ? 'POSIX signals required' : false,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}

Future<void> _runParent() async {
  final tempDirectory = await Directory.systemTemp.createTemp(
    'fvm_process_service_signal_',
  );

  try {
    final context = FvmContext.create(
      debugLabel: 'process-service-signal-parent',
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

    try {
      final result = await context.get<ProcessService>().run(
            Platform.resolvedExecutable,
            args: [Platform.script.toFilePath()],
            environment: {
              ...Platform.environment,
              _roleEnvironmentKey: _childRole,
            },
            echoOutput: true,
            throwOnError: false,
          );
      stdout.writeln(
        '${_markerPrefix}PARENT_UNEXPECTED_RESULT:${result.exitCode}',
      );
      exitCode = 3;
    } on ForceExit catch (error) {
      stdout.writeln('${_markerPrefix}PARENT_FORCE_EXIT:${error.exitCode}');
      exitCode = error.exitCode;
    }
    await stdout.flush();
  } finally {
    await tempDirectory.delete(recursive: true);
  }
}

Future<void> _runChild() async {
  final received = Completer<ProcessSignal>();
  final subscriptions = [
    for (final signal in [ProcessSignal.sigterm, ProcessSignal.sighup])
      signal.watch().listen((signal) {
        if (!received.isCompleted) received.complete(signal);
      }),
  ];

  try {
    stdout.writeln('${_markerPrefix}CHILD_READY:$pid');
    await stdout.flush();
    final signal = await received.future;

    stdout.writeln('${_markerPrefix}CHILD_SIGNAL:$signal');
    await stdout.flush();
    // Stands in for Flutter stopping its frontend_server and device processes.
    await Future<void>.delayed(const Duration(milliseconds: 250));

    stdout.writeln('${_markerPrefix}CHILD_CLEANUP_DONE');
    await stdout.flush();
    exitCode = 128 + signal.signalNumber;
  } finally {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
}
