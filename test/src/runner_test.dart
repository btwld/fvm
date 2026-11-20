import 'package:args/command_runner.dart';
import 'package:io/io.dart';
import 'package:test/test.dart';

import '../testing_utils.dart';

void main() {
  test('reports an unknown command instead of printing the version', () async {
    final runner = TestFactory.fastCommandRunner();

    await expectLater(
      () => runner.runOrThrow(['fvm', 'fluter', '--version']),
      throwsA(
        isA<UsageException>().having(
          (error) => error.message,
          'message',
          contains('fluter'),
        ),
      ),
    );
    expect(
      await runner.run(['fvm', 'fluter', '--version']),
      ExitCode.usage.code,
    );
  });
}
