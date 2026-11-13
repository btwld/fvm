import '../models/cache_flutter_version_model.dart';
import '../services/flutter_service.dart';
import '../utils/exceptions.dart';
import 'workflow.dart';

class SetupFlutterWorkflow extends Workflow {
  const SetupFlutterWorkflow(super.context);

  Future<void> call(CacheFlutterVersion version) async {
    // Skip setup if version has already been setup.
    if (version.isSetup) return;

    logger
      ..info('Setting up Flutter SDK: ${version.name}')
      ..info();

    try {
      final result = await get<FlutterService>().setup(version);
      if (result.exitCode != 0) {
        throw AppException(
          'Flutter SDK setup exited with code ${result.exitCode}. '
          'Fix the error above and try again.',
        );
      }
      logger
        ..info()
        ..success('Flutter SDK: ${version.printFriendlyName} is setup');
    } on ForceExit {
      rethrow;
    } on Exception catch (_) {
      logger.err('Failed to setup Flutter SDK');

      rethrow;
    }
  }
}
