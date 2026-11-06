"""Draft pull requests must not run any job."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1] / 'workflows'
PULL_REQUEST_WORKFLOWS = ('test-docs.yml', 'test-install.yml', 'test.yml')
ACTIVITY_TYPES = ('opened', 'synchronize', 'reopened', 'ready_for_review')
# `== false` is false when the pull_request context is missing, so push,
# schedule, workflow_dispatch, and reusable release calls would skip too.
DRAFT_GUARD = 'github.event.pull_request.draft != true'


def runs_for_draft_value(draft):
    """Return whether `draft != true` allows a job to run.

    Missing pull_request context is None. None and False both run; True skips.
    """
    return draft is not True


def _indent(line):
    return len(line) - len(line.lstrip(' '))


def _prepare(text):
    lines = []
    for raw in text.splitlines():
        stripped = raw.strip()
        if not stripped or stripped.startswith('#'):
            continue
        lines.append(raw.rstrip())
    return lines


def _mapping(lines):
    """Direct keys at the indent of the first line. Nested lines stay unparsed."""
    if not lines:
        return {}
    indent = _indent(lines[0])
    entries = {}
    index = 0
    while index < len(lines):
        line = lines[index]
        if _indent(line) != indent:
            raise ValueError(f'expected indent {indent}: {line!r}')
        key, _, rest = line[indent:].partition(':')
        index += 1
        nested = []
        while index < len(lines) and _indent(lines[index]) > indent:
            nested.append(lines[index])
            index += 1
        if nested:
            entries[key] = nested
        elif rest.strip():
            entries[key] = rest.strip()
        else:
            entries[key] = None
    return entries


def _items(lines):
    return [line.strip()[2:].strip().strip('"').strip("'")
            for line in lines if line.strip().startswith('- ')]


def _property(body, name):
    indent = _indent(body[0])
    prefix = f'{name}:'
    for line in body:
        if _indent(line) == indent and line.strip().startswith(prefix):
            return line.strip()[len(prefix):].strip()
    return ''


def workflows():
    return sorted(ROOT.glob('*.yml')) + sorted(ROOT.glob('*.yaml'))


class DraftCiTests(unittest.TestCase):
    def test_draft_guard_runs_for_non_pull_request_events(self):
        self.assertTrue(runs_for_draft_value(None))
        self.assertTrue(runs_for_draft_value(False))
        self.assertFalse(runs_for_draft_value(True))

    def test_pull_request_workflows_skip_every_job_while_draft(self):
        found = []
        for path in workflows():
            sections = _mapping(_prepare(path.read_text(encoding='utf-8')))
            trigger = _mapping(sections['on'])
            if 'pull_request' not in trigger:
                continue
            found.append(path.name)
            pull = _mapping(trigger['pull_request'])
            self.assertEqual(tuple(_items(pull['types'])), ACTIVITY_TYPES, path.name)
            self.assertIn('push', trigger, path.name)
            jobs = _mapping(sections['jobs'])
            self.assertTrue(jobs, path.name)
            for name, body in jobs.items():
                where = f'{path.name}:{name}'
                self.assertIsInstance(body, list, where)
                condition = ' '.join(_property(body, 'if').split())
                self.assertIn(DRAFT_GUARD, condition, where)
                self.assertNotIn('draft == false', condition, where)
                self.assertNotIn('exit 1', condition, where)
                if _property(body, 'needs') == 'validate':
                    self.assertIn("needs.validate.result == 'success'", condition, where)
            for line in path.read_text(encoding='utf-8').splitlines():
                code = line.split('#', 1)[0]
                if 'pull_request.draft' not in code:
                    continue
                self.assertIn('if:', code, path.name)
                self.assertIn(DRAFT_GUARD, code, path.name)
        self.assertEqual(tuple(found), PULL_REQUEST_WORKFLOWS)

    def test_existing_non_draft_triggers_stay(self):
        triggers = {}
        for path in workflows():
            sections = _mapping(_prepare(path.read_text(encoding='utf-8')))
            triggers[path.name] = _mapping(sections['on'])
        self.assertIn('workflow_call', triggers['test.yml'])
        self.assertIn('workflow_dispatch', triggers['test.yml'])
        self.assertIn('workflow_dispatch', triggers['test-install.yml'])
        self.assertIn('schedule', triggers['data.yaml'])
        self.assertNotIn('pull_request', triggers['release.yml'])
        ignored = _items(_mapping(triggers['test.yml']['pull_request'])['paths-ignore'])
        self.assertIn('docs/**', ignored)
        doc_paths = _items(_mapping(triggers['test-docs.yml']['pull_request'])['paths'])
        self.assertIn('docs/**', doc_paths)
        install_paths = _items(_mapping(triggers['test-install.yml']['pull_request'])['paths'])
        self.assertIn('docs/public/install.sh', install_paths)
        self.assertIn('.github/workflows/test-install.yml', install_paths)
