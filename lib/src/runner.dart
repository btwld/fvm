import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:io/ansi.dart';
import 'package:io/io.dart';
import 'package:pub_updater/pub_updater.dart';

import 'commands/api_command.dart';
import 'commands/cleanup_command.dart';
import 'commands/config_command.dart';
import 'commands/dart_command.dart';
import 'commands/destroy_command.dart';
import 'commands/doctor_command.dart';
import 'commands/exec_command.dart';
import 'commands/flavor_command.dart';
import 'commands/flutter_command.dart';
import 'commands/fork_command.dart';
import 'commands/global_command.dart';
import 'commands/install_command.dart';
import 'commands/integration_test_command.dart';
import 'commands/list_command.dart';
import 'commands/releases_command.dart';
import 'commands/remove_command.dart';
import 'commands/spawn_command.dart';
import 'commands/use_command.dart';
import 'models/config_model.dart';
import 'models/log_level_model.dart';
import 'services/logger_service.dart';
import 'utils/constants.dart';
import 'utils/context.dart';
import 'utils/exceptions.dart';
import 'version.dart';

/// Command Runner for FVM
class FvmCommandRunner extends CompletionCommandRunner<int> {
  final FvmContext context;
  final PubUpdater _pubUpdater;

  /// Constructor
  FvmCommandRunner(this.context, {PubUpdater? pubUpdater})
      : _pubUpdater = pubUpdater ?? PubUpdater(),
        super(kPackageName, kDescription) {
    argParser
      ..addFlag('verbose', help: 'Print verbose output.', negatable: false)
      ..addFlag(
        'version',
        abbr: 'v',
        help: 'Print the current version.',
        negatable: false,
      );
    addCommand(InstallCommand(context));
    addCommand(UseCommand(context));
    addCommand(ListCommand(context));
    addCommand(CleanupCommand(context));
    addCommand(RemoveCommand(context));
    addCommand(ReleasesCommand(context));
    addCommand(FlutterCommand(context));
    addCommand(DartCommand(context));
    addCommand(ForkCommand(context));
    addCommand(DoctorCommand(context));
    addCommand(SpawnCommand(context));
    addCommand(ConfigCommand(context));
    addCommand(ExecCommand(context));
    addCommand(DestroyCommand(context));
    addCommand(APICommand(context));
    addCommand(GlobalCommand(context));
    addCommand(FlavorCommand(context));
    addCommand(IntegrationTestCommand(context));
  }

  /// Checks if the current version (set by the build runner on the
  /// version.dart file) is the most recent one. If not, show a prompt to the
  /// user.
  Future<Function()?> _checkForUpdates() async {
    try {
      final lastUpdateCheck = context.lastUpdateCheck ?? DateTime.now();
      if (context.updateCheckDisabled) return null;
      final oneDay = lastUpdateCheck.add(const Duration(days: 1));

      if (DateTime.now().isBefore(oneDay)) {
        return null;
      }

      LocalAppConfig.read(path: context.appConfigPath)
        ..lastUpdateCheck = DateTime.now()
        ..save(path: context.appConfigPath);

      final isUpToDate = await _pubUpdater.isUpToDate(
        packageName: kPackageName,
        currentVersion: packageVersion,
      );

      if (isUpToDate) return null;

      final latestVersion = await _pubUpdater.getLatestVersion(kPackageName);

      return () {
        final updateAvailableLabel = lightYellow.wrap('Update available!');
        final currentVersionLabel = lightCyan.wrap(packageVersion);
        final latestVersionLabel = lightCyan.wrap(latestVersion);

        logger
          ..info()
          ..info(
            '$updateAvailableLabel $currentVersionLabel \u2192 $latestVersionLabel',
          )
          ..info();
      };
    } catch (_) {
      return () {
        logger.debug("Failed to check for updates.");
      };
    }
  }

  /// Checks for deprecated environment variables and shows warnings
  void _checkDeprecatedEnvironmentVariables() {
    // Check for deprecated variables (no longer supported)
    final deprecatedVars = {'FVM_GIT_CACHE': 'FVM_FLUTTER_URL'};

    // Check for legacy variables (still supported but discouraged)
    final legacyVars = {'FVM_HOME': 'FVM_CACHE_PATH'};

    var hasDeprecated = false;
    for (final entry in deprecatedVars.entries) {
      if (context.environment.containsKey(entry.key)) {
        if (!hasDeprecated) {
          logger.warn('Deprecated environment variables detected:');
          hasDeprecated = true;
        }
        logger.warn('  ${entry.key} → Use ${entry.value} instead');
      }
    }

    var hasLegacy = false;
    for (final entry in legacyVars.entries) {
      if (context.environment.containsKey(entry.key) &&
          !context.environment.containsKey(entry.value)) {
        if (!hasLegacy) {
          logger.info('Legacy environment variables detected:');
          hasLegacy = true;
        }
        logger.info('  ${entry.key} → Consider using ${entry.value}');
      }
    }

    if (hasDeprecated || hasLegacy) logger.info('');
  }

  Logger get logger => context.get();

  @override
  void printUsage() => logger.info(usage);

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final argResults = parse(args);

      if (argResults['verbose'] == true) {
        logger.level = Level.verbose;
      }

      final exitCode = await runCommand(argResults) ?? ExitCode.success.code;

      return exitCode;
    } on ForceExit catch (e) {
      logger.info(e.message);

      return e.exitCode;
    } on AppDetailedException catch (err, stackTrace) {
      logger
        ..fail(err.message)
        ..err()
        ..err(err.info);
      logger.logTrace(stackTrace);

      return ExitCode.unavailable.code;
    } on FileSystemException catch (err, stackTrace) {
      if (checkIfNeedsPrivilegePermission(err)) {
        logger
          ..info()
          ..fail('Requires administrator privileges to run this command.')
          ..info();

        logger.notice(
          "You don't have the required privileges to run this command.\n"
          "Try running with sudo or administrator privileges.\n"
          "If you are on Windows, you can turn on developer mode: https://bit.ly/3vxRr2M",
        );

        return ExitCode.noPerm.code;
      }

      logger
        ..err(err.message)
        ..info()
        ..err('Path: ${err.path}');
      logger.logTrace(stackTrace);

      return ExitCode.ioError.code;
    } on AppException catch (err) {
      logger.fail(err.message);

      return ExitCode.data.code;
    } on ProcessException catch (e) {
      logger
        ..info()
        ..err(e.toString())
        ..info();

      return e.errorCode;
    } on UsageException catch (err) {
      // On usage errors, show the commands usage message and
      // exit with an error code
      logger
        ..err(err.message)
        ..info()
        ..info(err.usage);

      return ExitCode.usage.code;
    } on Exception catch (err, stackTrace) {
      logger
        ..info()
        ..err(err.toString());

      logger.logTrace(stackTrace);

      return ExitCode.unavailable.code;
    }
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    // Verbose logs
    logger
      ..debug('')
      ..debug('Argument information:');

    if (topLevelResults.command?.name == 'completion') {
      super.runCommand(topLevelResults);

      return ExitCode.success.code;
    }

    if (topLevelResults.command?.name == 'api') {
      await super.runCommand(topLevelResults);

      return ExitCode.success.code;
    }

    final hasTopLevelOption = topLevelResults.options.any(
      (e) => topLevelResults.wasParsed(e),
    );

    if (hasTopLevelOption) {
      logger.debug('  Top level options:');
      for (final option in topLevelResults.options) {
        if (topLevelResults.wasParsed(option)) {
          logger.debug('  - $option: ${topLevelResults[option]}');
        }
      }
      logger.debug('');
    }

    if (topLevelResults.command != null) {
      final commandResult = topLevelResults.command!;
      logger.debug('Command: ${commandResult.name}');

      // Check if any command option was parsed
      final hasCommandOption = commandResult.options.any(
        (e) => commandResult.wasParsed(e),
      );

      if (hasCommandOption) {
        logger.debug('  Command options:');
        for (final option in commandResult.options) {
          if (commandResult.wasParsed(option)) {
            logger.debug('    - $option: ${commandResult[option]}');
          }
        }
      }

      logger.debug('');
    }

    // Check for deprecated environment variables
    _checkDeprecatedEnvironmentVariables();

    final checkingForUpdate = _checkForUpdates();

    // Run the command or show version
    final int? exitCode;
    // An unknown command (e.g. `fvm fluter --version`) lands in `rest`; let
    // the base runner report it instead of printing the version.
    if (topLevelResults['version'] == true && topLevelResults.rest.isEmpty) {
      logger.info(packageVersion);
      exitCode = ExitCode.success.code;
    } else {
      exitCode = await super.runCommand(topLevelResults);
    }

    final logOutput = await checkingForUpdate;
    logOutput?.call();

    return exitCode;
  }

  /// Disable auto-install of shell completions to avoid PathAccessException
  /// in managed environments (Nix/Home Manager) where shell configs are read-only.
  /// Users can still manually install completions via `fvm completion install`.
  @override
  bool get enableAutoInstall => false;
}
