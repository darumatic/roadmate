#!/usr/bin/env python3
"""Offline unit tests for scripts/notify.py (no network)."""

import io
import os
import tempfile
import unittest

import notify


class FakeResponse:
    def __init__(self, status=200):
        self.status = status

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class ReadTopicTest(unittest.TestCase):
    def test_missing_file_is_none(self):
        self.assertIsNone(notify.read_topic('/nonexistent/topic'))

    def test_empty_file_is_none(self):
        with tempfile.NamedTemporaryFile('w', suffix='.topic') as handle:
            handle.write('   \n')
            handle.flush()
            self.assertIsNone(notify.read_topic(handle.name))

    def test_topic_is_stripped(self):
        with tempfile.NamedTemporaryFile('w', suffix='.topic') as handle:
            handle.write('  roadmate-abc123\n')
            handle.flush()
            self.assertEqual(notify.read_topic(handle.name), 'roadmate-abc123')


class SendTest(unittest.TestCase):
    def test_no_topic_is_silent_noop(self):
        calls = []
        # read_topic falls back to the real file; force the unconfigured path
        # by pointing at a definitely-missing file instead.
        original = notify.TOPIC_FILE
        notify.TOPIC_FILE = '/nonexistent/topic'
        try:
            ok = notify.send('t', 'm',
                             urlopen=lambda *a, **k: calls.append(a))
        finally:
            notify.TOPIC_FILE = original
        self.assertFalse(ok)
        self.assertEqual(calls, [])

    def test_posts_title_and_message_to_topic(self):
        seen = {}

        def fake_urlopen(request, timeout=None):
            seen['url'] = request.full_url
            seen['title'] = request.get_header('Title')
            seen['data'] = request.data
            return FakeResponse(200)

        ok = notify.send('Backup FAILED', 'check the log',
                         topic='roadmate-xyz', urlopen=fake_urlopen)
        self.assertTrue(ok)
        self.assertEqual(seen['url'], 'https://ntfy.sh/roadmate-xyz')
        self.assertEqual(seen['title'], 'Backup FAILED')
        self.assertEqual(seen['data'], b'check the log')

    def test_network_error_returns_false_not_raise(self):
        def boom(request, timeout=None):
            raise OSError('no network')

        self.assertFalse(notify.send('t', 'm', topic='x', urlopen=boom))


if __name__ == '__main__':
    unittest.main(verbosity=1)
