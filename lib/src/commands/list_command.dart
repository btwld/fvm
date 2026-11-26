import 'package:dart_console/dart_console.dart';
import 'package:mason_logger/mason_logger.dart';

import '../models/cache_flutter_version_model.dart';
import '../models/project_registry_model.dart';
import '../services/cache_service.dart';
import '../services/logger_service.dart';
import '../services/project_registry_service.dart';
import '../services/project_service.dart';
import '../services/releases_service/models/flutter_releases_model.dart';
import '../services/releases_service/releases_client.dart';
import '../utils/exceptions.dart';
import '../utils/helpers.dart';
import 'base_command.dart';

/// List installed SDK Versions
class ListCommand extends BaseFvmCommand {
  @override
  final name = 'list';

  @override
  final description = 'Lists all Flutter SDK versions installed by FVM';

  ListCommand(super.context);

  /// Displays a formatted table of Flutter SDK versions
  void displayVersionsTable(
    List<CacheFlutterVersion> cacheVersions,
    FlutterReleasesResponse releases,
    CacheFlutterVersion? globalVersion,
    String? localVersion,
    CacheProjectUsage? usage,
  ) {
    final table = Table()
      ..insertColumn(header: 'Version', alignment: TextAlignment.left)
      ..insertColumn(header: 'Channel', alignment: TextAlignment.left)
      ..insertColumn(header: 'Flutter Version', alignment: TextAlignment.left)
      ..insertColumn(header: 'Dart Version', alignment: TextAlignment.left)
      ..insertColumn(header: 'Release Date', alignment: TextAlignment.left)
      ..insertColumn(header: 'Global', alignment: TextAlignment.left)
      ..insertColumn(header: 'Local', alignment: TextAlignment.left)
      ..insertColumn(header: 'Projects', alignment: TextAlignment.left);

    for (var version in cacheVersions) {
      var printVersion = version.nameWithAlias;
      final latestRelease =
          version.isChannel && !version.isMain && !version.fromFork
              ? releases.latestChannelRelease(version.name)
              : null;

      // Look up release information
      final release = releases.fromVersion(version.flutterSdkVersion ?? '');

      String releaseDate = '';
      String channel = '';

      if (release != null) {
        releaseDate = friendlyDate(release.releaseDate);
        channel = release.channel.name;
      }

      String flutterSdkVersion = version.flutterSdkVersion ?? '';

      // Generate version output with formatting
      String getVersionOutput() {
        if (version.isNotSetup) {
          return flutterSdkVersion = '${yellow.wrap('Need setup*')}';
        }
        if (latestRelease != null &&
            flutterSdkVersion.isNotEmpty &&
            latestRelease.version != flutterSdkVersion) {
          return '$flutterSdkVersion ${Icons.arrowRight} ${(green.wrap(latestRelease.version))}';
        }

        return flutterSdkVersion;
      }

      String projectsCell() {
        if (usage == null) return '-';
        if (usage.isUnused(printVersion)) {
          return yellow.wrap('Unused') ?? 'Unused';
        }

        return '${usage.countFor(printVersion)}';
      }

      // Add row to the table with proper null safety
      table
        ..insertRows([
          [
            printVersion,
            channel,
            getVersionOutput(),
            version.dartSdkVersion ?? '',
            releaseDate,
            globalVersion == version ? (green.wrap(Icons.circle) ?? '') : '',
            localVersion == printVersion && localVersion != null
                ? (green.wrap(Icons.circle) ?? '')
                : '',
            projectsCell(),
          ],
        ])
        ..borderStyle = BorderStyle.square
        ..borderColor = ConsoleColor.white
        ..borderType = BorderType.grid
        ..headerStyle = FontStyle.bold;
    }

    logger.info(table.toString());
  }

  @override
  Future<int> run() async {
    final cacheVersions = await get<CacheService>().getAllVersions();

    final directorySize = await getFullDirectorySize(cacheVersions, logger);

    logger
      ..info('Cache directory:  ${cyan.wrap(context.versionsCachePath)}')
      ..info('Directory Size: ${formatFriendlyBytes(directorySize)}')
      ..info();

    // Notify the user if any versions need setup
    if (cacheVersions.any((e) => e.isNotSetup)) {
      logger
        ..warn(
          'Some versions might still require finishing setup - SDKs have been cloned, but they have not downloaded their dependencies.',
        )
        ..info(
          'This will complete the first time you run any command with the SDK.',
        )
        ..info('');
    }

    // Early return if no versions are installed
    if (cacheVersions.isEmpty) {
      logger
        ..info('No SDKs have been installed yet. Flutter. SDKs')
        ..info('installed outside of fvm will not be displayed.');

      return ExitCode.success.code;
    }

    // Fetch releases and get versions for table display
    final releases = await get<FlutterReleaseClient>().fetchReleases();
    final globalVersion = get<CacheService>().getGlobal();
    final project = get<ProjectService>().findAncestor();
    final pinned = project.pinnedVersion;
    // Match on the cached name, not nameWithAlias: a forked `x@channel` pin
    // installs to `<fork>/x`, so the two differ for those versions.
    final localVersion =
        pinned == null ? null : get<CacheService>().installedNameOf(pinned);

    // An unreadable registry only costs the Projects column, never the list.
    CacheProjectUsage? usage;
    try {
      usage = get<ProjectRegistryService>().calculateUsage(
        includeCurrent: project,
      );
    } on ProjectRegistryException catch (error, stackTrace) {
      logger.warn('$error');
      logger.logTrace(stackTrace);
    }

    // Display the table with versions
    displayVersionsTable(
      cacheVersions,
      releases,
      globalVersion,
      localVersion,
      usage,
    );

    if (pinned == null) {
      logger.info(
        'Local shows the SDK pinned by the project in the current directory; '
        'none is configured here.',
      );
    } else if (localVersion == null ||
        !cacheVersions.any(
          (version) => version.nameWithAlias == localVersion,
        )) {
      logger.info(
        'Local version ${pinned.nameWithAlias} is configured but not cached.',
      );
    }

    if (usage != null) {
      logger.info(
        '"Unused" means no project known to FVM pins that SDK. Projects are '
        'recorded when you run fvm use or fvm install inside them. '
        'Run "fvm cleanup" to review removal and cached patch upgrades.',
      );
    }

    return ExitCode.success.code;
  }

  @override
  List<String> get aliases => ['ls'];
}
