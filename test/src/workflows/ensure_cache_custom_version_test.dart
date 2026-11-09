import 'package:fvm/fvm.dart';
import 'package:fvm/src/services/flutter_service.dart';
import 'package:fvm/src/services/logger_service.dart';
import 'package:fvm/src/workflows/ensure_cache.workflow.dart';
import 'package:test/test.dart';

import '../../testing_utils.dart';

void main() {
  test(
    'custom local SDK does not warn when metadata differs from the label',
    () async {
      final context = TestFactory.fastContext(
        generators: {
          Logger: (context) => RecordingLogger(context),
        },
      );
      final logger = context.get<Logger>() as RecordingLogger;
      logger.level = Level.info;
      final flutterService =
          context.get<FlutterService>() as FakeFlutterService;

      final version = FlutterVersion.parse('custom_flock_dev');
      FakeFlutterSdkFixture.install(
        context,
        version,
        state: FakeFlutterSdkState.versionMismatch,
        mismatchCachedVersion: '3.50.0-1.0.pre-369',
      );

      final cacheService = context.get<CacheService>();
      final cached = cacheService.getVersion(version);
      expect(cached?.flutterSdkVersion, '3.50.0-1.0.pre-369');

      final integrity = await cacheService.verifyCacheIntegrity(cached!);
      final installCountBefore = flutterService.installedVersions.length;
      final result = await EnsureCacheWorkflow(context).call(
        version,
        maintainGitCacheOnHit: false,
      );

      expect(result.name, 'custom_flock_dev');
      expect(flutterService.installedVersions.length, installCountBefore);
      expect(integrity, CacheIntegrity.valid);
      expect(logger.warnings, isEmpty);
      expect(
        logger.debugMessages,
        contains(
          'Not checking for version mismatch as local version is being used.',
        ),
      );
    },
  );
}

class RecordingLogger extends Logger {
  final List<String> warnings = [];
  final List<String> debugMessages = [];

  RecordingLogger(super.context);

  @override
  void warn([String message = '']) {
    warnings.add(message);
    super.warn(message);
  }

  @override
  void debug([String message = '']) {
    debugMessages.add(message);
    super.debug(message);
  }
}
