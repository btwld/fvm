from io import BytesIO
import json
from pathlib import Path
import tempfile
import unittest

from update_release_feeds import PLATFORMS, refresh


class FeedTests(unittest.TestCase):
    def test_refreshes_all_feeds_and_ignores_formatting_only_changes(self):
        data = {'releases': [{'version': '1.0'}], 'base_url': 'https://example.invalid'}
        with tempfile.TemporaryDirectory() as folder:
            def fetch(url, timeout):
                self.assertEqual(timeout, 30)
                self.assertTrue(url.endswith('.json'))
                return BytesIO(json.dumps(data).encode())
            self.assertEqual(set(refresh(folder, fetch)),
                             {f'releases_{p}.json' for p in PLATFORMS})
            before = {p.name: p.read_bytes() for p in Path(folder).iterdir()}
            def reformatted(url, timeout):
                return BytesIO(json.dumps(data, indent=4, sort_keys=True).encode())
            self.assertEqual(refresh(folder, reformatted), [])
            self.assertEqual(before, {p.name: p.read_bytes() for p in Path(folder).iterdir()})

    def test_failed_or_invalid_feed_leaves_every_file_unchanged(self):
        for failure in ('network', 'json', 'schema'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                for p in PLATFORMS:
                    (root / f'releases_{p}.json').write_text('{"releases": []}')
                before = {p.name: p.read_bytes() for p in root.iterdir()}
                def fetch(url, timeout):
                    if url.endswith('releases_windows.json'):
                        if failure == 'network':
                            raise OSError('offline')
                        return BytesIO(b'broken' if failure == 'json' else b'[]')
                    return BytesIO(b'{"releases": [{"version": "new"}]}')
                with self.assertRaises((OSError, ValueError)):
                    refresh(folder, fetch)
                self.assertEqual(before, {p.name: p.read_bytes() for p in root.iterdir()})


if __name__ == '__main__':
    unittest.main()
