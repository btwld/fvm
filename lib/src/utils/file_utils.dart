import 'dart:io';

import 'package:path/path.dart' as p;

import 'exceptions.dart';

/// Rejects links, including dangling links, from the trusted root to the leaf.
void checkManagedPath(String root, String target) {
  final base = p.normalize(p.absolute(root));
  final destination = p.normalize(p.absolute(target));
  if (!p.isWithin(base, destination)) {
    throw AppException('Expected a path inside $base: $target');
  }
  var current = base;
  for (final part in p.split(p.relative(destination, from: base))) {
    current = p.join(current, part);
    if (FileSystemEntity.isLinkSync(current)) {
      throw AppException('Refusing to follow a link at $current');
    }
  }
}

/// Whether [error] indicates that another process currently holds a file lock.
bool isFileLockContentionError(FileSystemException error) {
  if (Platform.isWindows) {
    final errorCode = error.osError?.errorCode;
    if (errorCode == 32 || errorCode == 33) return true;
  }

  final message = error.message.toLowerCase();

  return message.contains('lock failed') ||
      message.contains('resource temporarily unavailable') ||
      message.contains('operation would block') ||
      message.contains('already locked') ||
      message.contains('being used by another process');
}

/// Deletes [directory] with retries on Windows to work around file locks.
///
/// Returns `true` when the directory no longer exists. On failure the last
/// [FileSystemException] is either rethrown ([requireSuccess] = true) or
/// forwarded to [onFinalError] before returning `false`.
Future<bool> deleteDirectoryWithRetry(
  Directory directory, {
  bool requireSuccess = true,
  int windowsAttempts = 5,
  Duration retryDelay = const Duration(milliseconds: 200),
  void Function(FileSystemException error)? onFinalError,
}) async {
  if (!directory.existsSync()) return true;

  final attempts = Platform.isWindows ? windowsAttempts : 1;
  for (var attempt = 1; attempt <= attempts; attempt++) {
    try {
      directory.deleteSync(recursive: true);

      return true;
    } on FileSystemException catch (error) {
      final isLastAttempt = attempt == attempts;
      if (isLastAttempt) {
        if (requireSuccess) rethrow;
        onFinalError?.call(error);

        return false;
      }
      await Future<void>.delayed(retryDelay * attempt);
    }
  }

  return false;
}
