import 'dart:io';

import 'package:path/path.dart';

String? which(String command, {bool binDir = false}) {
  String? pathEnv = Platform.environment['PATH'];
  String? pathExtEnv =
      Platform.isWindows ? Platform.environment['PATHEXT'] : null;

  if (pathEnv == null) {
    return null;
  }

  List<String> paths = pathEnv.split(Platform.isWindows ? ';' : ':');
  List<String> possibleExtensions =
      pathExtEnv != null ? pathExtEnv.split(';') : [''];

  for (String dir in paths) {
    if (Platform.isWindows && !isAbsolute(dir)) continue;
    String fullPath = join(dir, command);
    File exec = File(fullPath);

    if (exec.existsSync()) {
      final execPath = exec.absolute.path;

      return binDir ? dirname(execPath) : execPath;
    }

    if (Platform.isWindows && pathExtEnv != null) {
      for (var ext in possibleExtensions) {
        String winPath = '$fullPath$ext';
        exec = File(winPath);
        if (exec.existsSync()) {
          final execPath = exec.absolute.path;

          return binDir ? dirname(execPath) : execPath;
        }
      }
    }
  }

  return null;
}
