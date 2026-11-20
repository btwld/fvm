import 'dart:io';

import 'package:fvm/src/utils/helpers.dart';
import 'package:fvm/src/version.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('Does CLI version match', () async {
    final yaml = File(
      join(Directory.current.path, 'pubspec.yaml'),
    ).readAsStringSync();
    final pubspec = loadYamlNode(yaml);
    expect(pubspec.value['version'], packageVersion);
  });

  test('Test update env variables', () async {
    final envVars = Platform.environment;
    // final version = 'stable';
    final envName = 'PATH';
    final fakePath = 'FAKE_PATH';

    final newEnvVar = updateEnvironmentVariables([
      'FAKE_PATH',
      'ANOTHER_FAKE_PATH',
    ], envVars);

    // expect(newEnvVar[envName], envVars[envName]);
    expect(newEnvVar[envName], contains(fakePath));
    expect(newEnvVar[envName], contains('ANOTHER_FAKE_PATH'));
    expect(envVars, isNot(newEnvVar));
  });

  test('Assigns version weights', () async {
    expect('500.0.0', assignVersionWeight('2da03e5'));
    expect('500.0.0', assignVersionWeight('ce18d702e9'));
    expect(
      '500.0.0',
      assignVersionWeight('ce18d702e90d3dff9fee53d61a770c94f14f2811'),
    );
    expect('400.0.0', assignVersionWeight('master'));
    expect('300.0.0', assignVersionWeight('stable'));
    expect('200.0.0', assignVersionWeight('beta'));
    expect('100.0.0', assignVersionWeight('dev'));
  });

  test('Assigns main channel the same weight as master', () async {
    // `main` is a valid Flutter channel (see kFlutterChannels) and is treated
    // as a mainline channel alongside `master` (see FlutterVersion.isMain), so
    // it must get the same comparison weight. Otherwise it falls through to
    // Version.parse('main'), which fails and ranks `main` as invalid (0.0.0),
    // below every real channel.
    expect(assignVersionWeight('main'), '400.0.0');
    expect(assignVersionWeight('main'), assignVersionWeight('master'));
  });

  group('isValidGitUrl', () {
    test('accepts common git transports with .git suffix', () {
      expect(isValidGitUrl('https://github.com/flutter/flutter.git'), isTrue);
      expect(isValidGitUrl('git://example.com/repo.git'), isTrue);
      expect(isValidGitUrl('ssh://git@github.com/flutter/flutter.git'), isTrue);
      expect(isValidGitUrl('file:///Users/test/projects/flutter.git'), isTrue);
    });

    test('accepts scp-style git urls including ipv6 hosts', () {
      expect(isValidGitUrl('git@github.com:flutter/flutter.git'), isTrue);
      expect(isValidGitUrl('git@[2001:db8::1]:owner/project.git'), isTrue);
    });

    test('accepts ssh urls that use scp-like namespace syntax', () {
      expect(isValidGitUrl('ssh://git@gitlab.com:group/project.git'), isTrue);
      expect(
        isValidGitUrl('ssh://git@gitlab.com:7999/group/project.git'),
        isTrue,
      );
    });

    test('accepts valid git URLs without .git suffix', () {
      expect(isValidGitUrl('https://github.com/flutter/flutter'), isTrue);
      expect(isValidGitUrl('ssh://git@github.com/flutter/flutter'), isTrue);
      expect(isValidGitUrl('git@github.com:flutter/flutter'), isTrue);
      expect(isValidGitUrl('file:///path/to/repo'), isTrue);
    });

    test('rejects malformed git urls', () {
      expect(isValidGitUrl('ssh://git@gitlab.com'), isFalse);
      expect(isValidGitUrl('not a url'), isFalse);
      expect(isValidGitUrl(''), isFalse);
    });

    test('rejects structurally invalid URLs', () {
      // Host-only: no repo path
      expect(isValidGitUrl('https://github.com'), isFalse);
      // Root-only: empty path
      expect(isValidGitUrl('https://github.com/'), isFalse);
      // Query-only: no path
      expect(isValidGitUrl('https://github.com?q=flutter'), isFalse);
    });

    test('rejects URLs with query or fragment suffixes', () {
      expect(
        isValidGitUrl('https://github.com/flutter/flutter.git?foo=1'),
        isFalse,
      );
      expect(isValidGitUrl('https://github.com/flutter/flutter#main'), isFalse);
      expect(
        isValidGitUrl('git@github.com:flutter/flutter.git?foo=1'),
        isFalse,
      );
      expect(isValidGitUrl('git@github.com:flutter/flutter.git#main'), isFalse);
    });

    test('accepts all valid git URL schemes', () {
      expect(isValidGitUrl('https://github.com/flutter/flutter.git'), isTrue);
      expect(isValidGitUrl('http://github.com/flutter/flutter.git'), isTrue);
      expect(isValidGitUrl('git://github.com/flutter/flutter.git'), isTrue);
      expect(isValidGitUrl('ssh://git@github.com/flutter/flutter.git'), isTrue);
      expect(isValidGitUrl('file:///path/to/repo.git'), isTrue);
    });
  });

  group('extractFlutterVersionOutput', () {
    test('should correctly parse the EXAMPLE:1', () {
      final content =
          '''Flutter 3.15.0-15.1.pre • channel beta • https://github.com/flutter/flutter.git
Framework • revision b2ec15bfa3 (5 days ago) • 2023-09-14 15:31:44 -0500
Engine • revision 5c86194494
Tools • Dart 3.2.0 (build 3.2.0-134.1.beta) • DevTools 2.27.0''';

      final result = extractFlutterVersionOutput(content);

      expect(result.flutterVersion, '3.15.0-15.1.pre');
      expect(result.channel, 'beta');
      expect(result.dartVersion, '3.2.0');
      expect(result.dartBuildVersion, '3.2.0-134.1.beta');
    });

    test('should correctly parse the EXAMPLE:2', () {
      final content =
          '''Flutter 3.10.5 • channel stable • https://github.com/flutter/flutter.git
Framework • revision 796c8ef792 (3 months ago) • 2023-06-13 15:51:02 -0700
Engine • revision 45f6e00911
Tools • Dart 3.0.5 • DevTools 2.23.1''';

      final result = extractFlutterVersionOutput(content);

      expect(result.flutterVersion, '3.10.5');
      expect(result.channel, 'stable');
      expect(result.dartVersion, '3.0.5');
      expect(result.dartBuildVersion, '3.0.5');
    });

    test('should correctly parse the EXAMPLE:3', () {
      final content =
          '''Flutter 2.2.0 • channel stable • https://github.com/flutter/flutter.git
Framework • revision b22742018b (2 years, 4 months ago) • 2021-05-14 19:12:57 -0700
Engine • revision a9d88a4d18
Tools • Dart 2.13.0''';

      final result = extractFlutterVersionOutput(content);

      expect(result.flutterVersion, '2.2.0');
      expect(result.channel, 'stable');
      expect(result.dartVersion, '2.13.0');
      expect(result.dartBuildVersion, '2.13.0');
    });

    test('should correctly parse the EXAMPLE:4', () {
      final content =
          '''  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                     Dload  Upload   Total   Spent    Left  Speed

      0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
     27  203M   27 56.1M    0     0  61.8M      0  0:00:03 --:--:--  0:00:03 61.8M
     88  203M   88  180M    0     0  94.9M      0  0:00:02  0:00:01  0:00:01 94.9M
    100  203M  100  203M    0     0  95.9M      0  0:00:02  0:00:02 --:--:-- 96.0M
    Resolving dependencies...
    + _fe_analyzer_shared 58.0.0 (64.0.0 available)
    + analyzer 5.10.0 (6.2.0 available)
    + archive 3.3.2 (3.3.9 available)
    + args 2.4.0 (2.4.2 available)
    + async 2.11.0
    + boolean_selector 2.1.1
    + browser_launcher 1.1.1
    + built_collection 5.1.1
    + built_value 8.4.4 (8.6.2 available)
    + checked_yaml 2.0.2 (2.0.3 available)
    + clock 1.1.1
    + collection 1.17.1 (1.18.0 available)
    + completion 1.0.1
    + convert 3.1.1
    + coverage 1.6.3
    + crypto 3.0.2 (3.0.3 available)
    + csslib 0.17.2 (1.0.0 available)
    + dds 2.7.10 (2.9.4 available)
    + dds_service_extensions 1.3.3 (1.6.0 available)
    + devtools_shared 2.23.0 (4.0.1 available)
    + dwds 19.0.0 (21.0.0 available)
    + fake_async 1.3.1
    + file 6.1.4 (7.0.0 available)
    + file_testing 3.0.0
    + fixnum 1.1.0
    + flutter_template_images 4.2.0 (4.2.1 available)
    + frontend_server_client 3.2.0
    + glob 2.1.1 (2.1.2 available)
    + html 0.15.2 (0.15.4 available)
    + http 0.13.5 (1.1.0 available)
    + http_multi_server 3.2.1
    + http_parser 4.0.2
    + intl 0.18.0 (0.18.1 available)
    + io 1.0.4
    + js 0.6.7
    + json_annotation 4.8.0 (4.8.1 available)
    + json_rpc_2 3.0.2
    + logging 1.1.1 (1.2.0 available)
    + matcher 0.12.15 (0.12.16 available)
    + meta 1.9.1 (1.10.0 available)
    + mime 1.0.4
    + multicast_dns 0.3.2+3 (0.3.2+4 available)
    + mustache_template 2.0.0
    + native_stack_traces 0.5.5 (0.5.6 available)
    + node_preamble 2.0.2
    + package_config 2.1.0
    + path 1.8.3
    + petitparser 5.3.0 (6.0.1 available)
    + platform 3.1.0 (3.1.2 available)
    + pool 1.5.1
    + process 4.2.4 (5.0.0 available)
    + pub_semver 2.1.3 (2.1.4 available)
    + pubspec_parse 1.2.2 (1.2.3 available)
    + shelf 1.4.0 (1.4.1 available)
    + shelf_packages_handler 3.0.1 (3.0.2 available)
    + shelf_proxy 1.0.2 (1.0.4 available)
    + shelf_static 1.1.1 (1.1.2 available)
    + shelf_web_socket 1.0.3 (1.0.4 available)
    + source_map_stack_trace 2.1.1
    + source_maps 0.10.12
    + source_span 1.9.1 (1.10.0 available)
    + sse 4.1.2
    + stack_trace 1.11.0 (1.11.1 available)
    + standard_message_codec 0.0.1+3 (0.0.1+4 available)
    + stream_channel 2.1.1 (2.1.2 available)
    + string_scanner 1.2.0
    + sync_http 0.3.1
    + term_glyph 1.2.1
    + test 1.24.1 (1.24.6 available)
    + test_api 0.5.1 (0.6.1 available)
    + test_core 0.5.1 (0.5.6 available)
    + typed_data 1.3.1 (1.3.2 available)
    + unified_analytics 1.1.0 (4.0.0 available)
    + usage 4.1.0 (4.1.1 available)
    + uuid 3.0.7 (4.0.0 available)
    + vm_service 11.3.0 (11.10.0 available)
    + vm_snapshot_analysis 0.7.2 (0.7.6 available)
    + watcher 1.0.2 (1.1.0 available)
    + web_socket_channel 2.3.0 (2.4.0 available)
    + webdriver 3.0.2
    + webkit_inspection_protocol 1.2.0 (1.2.1 available)
    + xml 6.2.2 (6.4.2 available)
    + yaml 3.1.1 (3.1.2 available)
    Changed 83 dependencies!
    53 packages have newer versions incompatible with dependency constraints.
    Try `dart pub outdated` for more information.
    Flutter 3.10.5 • channel stable • https://github.com/flutter/flutter.git
    Framework • revision 796c8ef792 (3 months ago) • 2023-06-13 15:51:02 -0700
    Engine • revision 45f6e00911
    Tools • Dart 3.0.5 • DevTools 2.23.1''';

      final result = extractFlutterVersionOutput(content);

      expect(result.flutterVersion, '3.10.5');
      expect(result.channel, 'stable');
      expect(result.dartVersion, '3.0.5');
      expect(result.dartBuildVersion, '3.0.5');
    });
  });

  test('should correctly parse the EXAMPLE:5', () {
    final content =
        '''Flutter 3.15.0-15.2.pre â€¢ channel beta â€¢ https://github.com/flutter/flutter.git
Framework â€¢ revision 0d074ced6c (12 hours ago) â€¢ 2023-09-21 10:24:15 -0700
Engine â€¢ revision 453411bcf3
Tools â€¢ Dart 3.2.0 (build 3.2.0-134.1.beta) â€¢ DevTools 2.27.0
''';

    final result = extractFlutterVersionOutput(content);

    expect(result.flutterVersion, '3.15.0-15.2.pre');
    expect(result.channel, 'beta');
    expect(result.dartVersion, '3.2.0');
    expect(result.dartBuildVersion, '3.2.0-134.1.beta');
  });

  test('formatFriendlyBytes', () {
    expect(formatFriendlyBytes(1024), '1.00 KB');
    expect(formatFriendlyBytes(1024 * 1024), '1.00 MB');
    expect(formatFriendlyBytes(1024 * 1024 * 1024), '1.00 GB');
    expect(formatFriendlyBytes(1024 * 1024 * 1024 * 1024), '1.00 TB');
    expect(formatFriendlyBytes(1024 * 1024 * 1024 * 1024 * 1024), '1.00 PB');
    expect(
      formatFriendlyBytes(1024 * 1024 * 1024 * 1024 * 1024 * 1024),
      '1.00 EB',
    );
  });
}
