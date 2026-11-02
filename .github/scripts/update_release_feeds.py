"""Refresh the three Flutter release feeds; fetch all before changing files."""
import json
from pathlib import Path
import tempfile
from urllib.request import urlopen

PLATFORMS = ('macos', 'windows', 'linux')
BASE_URL = 'https://storage.googleapis.com/flutter_infra_release/releases/'


def refresh(directory, fetch=urlopen):
    directory = Path(directory)
    pending = []
    for platform in PLATFORMS:
        name = f'releases_{platform}.json'
        with fetch(BASE_URL + name, timeout=30) as response:
            content = response.read()
        data = json.loads(content)
        if not isinstance(data, dict) or not isinstance(data.get('releases'), list):
            raise ValueError(f'Invalid release feed: {name}')
        path = directory / name
        try:
            previous = json.loads(path.read_bytes())
        except (FileNotFoundError, ValueError):
            previous = None
        if previous != data:
            pending.append((path, content))
    for path, content in pending:
        with tempfile.NamedTemporaryFile(dir=directory, delete=False) as temporary:
            temporary.write(content)
            staged = Path(temporary.name)
        try:
            staged.replace(path)
        finally:
            staged.unlink(missing_ok=True)
    return [path.name for path, _ in pending]


if __name__ == '__main__':
    print('Updated: ' + ', '.join(refresh('.')))
