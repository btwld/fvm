import unittest
from unittest.mock import patch

from ci_scope import needs_integration, scope


class ScopeTests(unittest.TestCase):
    def test_isolated_changes(self):
        self.assertFalse(needs_integration(['fvm_mcp/lib/server.dart',
                                            'tool/release_tool/test/release_test.dart',
                                            'README.md']))

    def test_cli_and_shared_inputs_always_run(self):
        for name in ['lib/src/services/git_service.dart', 'bin/main.dart',
                     'pubspec.yaml', 'pubspec.lock', 'tool/grind.dart',
                     'test/integration/use_test.dart', 'test/support_assets/a',
                     '.github/workflows/test.yml', '.github/scripts/ci_scope.py',
                     'fvm_mcp/../lib/cli.dart', '/fvm_mcp/foo', 'unknown']:
            with self.subTest(name=name):
                self.assertTrue(needs_integration(['fvm_mcp/lib/a.dart', name]))
        self.assertTrue(needs_integration([]))

    def test_events_and_uncertain_history_run_all(self):
        for event in ['push', 'workflow_call', 'workflow_dispatch', 'schedule', '']:
            self.assertTrue(scope(event, 'a' * 40))
        self.assertTrue(scope('pull_request', ''))
        # workflow_call inherits a pull_request caller's event and base SHA.
        self.assertTrue(scope('pull_request', 'a' * 40, reusable=True))
        with patch('ci_scope.subprocess.check_output', side_effect=OSError):
            self.assertTrue(scope('pull_request', 'a' * 40))

    def test_verified_merge_diff_and_mixed_changes(self):
        with patch('ci_scope.subprocess.check_output', side_effect=[
                'a' * 40 + ' ' + 'b' * 40, b'fvm_mcp/lib/a.dart\0']):
            self.assertFalse(scope('pull_request', 'a' * 40))
        with patch('ci_scope.subprocess.check_output', side_effect=[
                'a' * 40 + ' ' + 'b' * 40,
                b'fvm_mcp/lib/a.dart\0lib/src/commands/use.dart\0']):
            self.assertTrue(scope('pull_request', 'a' * 40))
        with patch('ci_scope.subprocess.check_output', return_value='c' * 40):
            self.assertTrue(scope('pull_request', 'a' * 40))


if __name__ == '__main__':
    unittest.main()
