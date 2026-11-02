"""Skip SDK-download suites only for isolated MCP/release-tool PR changes."""
import os
from pathlib import PurePosixPath
import re
import subprocess


def needs_integration(paths):
    if not paths:
        return True
    for name in paths:
        path = PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts:
            return True
        isolated = name.startswith(('fvm_mcp/', 'tool/release_tool/'))
        prose = len(path.parts) == 1 and path.suffix == '.md'
        if not (isolated or prose):
            return True
    return False


def scope(event, base, cwd=None, reusable=False):
    # Main pushes, reusable release callers and dispatches retain all suites.
    if reusable or event != 'pull_request' or not re.fullmatch(r'[0-9a-f]{40}', base):
        return True
    try:
        parents = subprocess.check_output(
            ['git', 'show', '-s', '--format=%P', 'HEAD'], cwd=cwd, text=True).split()
        if len(parents) != 2 or parents[0] != base:
            return True
        changed = subprocess.check_output(
            ['git', 'diff', '--no-ext-diff', '--name-only', '--no-renames', '-z',
             base, 'HEAD', '--'], cwd=cwd)
        return needs_integration([os.fsdecode(p) for p in changed.split(b'\0') if p])
    except (OSError, subprocess.CalledProcessError):
        return True


if __name__ == '__main__':
    heavy = scope(os.environ.get('GITHUB_EVENT_NAME', ''),
                  os.environ.get('PR_BASE_SHA', ''),
                  reusable=os.environ.get('REUSABLE_CALL') == 'true')
    with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
        output.write(f'integration={str(heavy).lower()}\n')
    print('Run integration and migration' if heavy else 'Isolated tools PR: unit suites only')
