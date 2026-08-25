#!/usr/bin/env python3
"""Offline unit tests for scripts/notify.py (no network)."""

import io
import os
import tempfile
import unittest
from unittest import mock

import notify


# The store release scripts run `flutter analyze` + `flutter test` with the
# release secrets already in the environment: mobile-release.yml exports
# ROADMATE_NTFY_TOPIC onto the very step that runs release_android.sh /
# release_ios.sh. read_topic() takes the environment *before* the file, so an
# ambient topic silently rewrites every "nothing is configured" expectation
# below - that is what failed the v1.0.19 Mobile Release twice, on both
# platforms, minutes into the build. Web CI never catches it, because
# web-release.yml exports the topic only on its final deploy step.
#
# A test that asserts on the *file* source must therefore own the environment.
# The env-before-file rule itself stays covered by TopicFromEnvTest, which
# passes its own `environ` dicts and never reads the ambient one.
_env_patch = None


def setUpModule():
    global _env_patch
    _env_patch = mock.patch.dict(os.environ, {}, clear=False)
    _env_patch.start()
    os.environ.pop(notify.TOPIC_ENV, None)


def tearDownModule():
    _env_patch.stop()


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


class TopicFromEnvTest(unittest.TestCase):
    """CI has no ~/.config/roadmate, so the release workflows pass the topic
    in the environment (GitHub secret NTFY_TOPIC)."""

    def test_env_topic_wins_over_the_file(self):
        self.assertEqual(
            notify.read_topic(path='/nonexistent',
                              environ={notify.TOPIC_ENV: 'from-env'}),
            'from-env')

    def test_env_topic_is_stripped(self):
        self.assertEqual(
            notify.read_topic(path='/nonexistent',
                              environ={notify.TOPIC_ENV: '  spaced  \n'}),
            'spaced')

    def test_empty_env_falls_back_to_the_file(self):
        with tempfile.NamedTemporaryFile('w', suffix='.topic',
                                         delete=False) as handle:
            handle.write('from-file\n')
            path = handle.name
        try:
            self.assertEqual(
                notify.read_topic(path=path, environ={notify.TOPIC_ENV: ''}),
                'from-file')
        finally:
            os.unlink(path)

    def test_no_topic_anywhere_is_none(self):
        self.assertIsNone(
            notify.read_topic(path='/nonexistent', environ={}))


class ReleaseAlertTest(unittest.TestCase):
    """Owner request 2026-08-25: a release alert for EVERY platform, and the
    version number is always in it."""

    def setUp(self):
        self.sent = []

    def record(self, title, message):
        self.sent.append((title, message))
        return True

    def test_version_is_in_the_title(self):
        notify.notify_release('Web', '1.0.18', send=self.record)
        title, message = self.sent[0]
        self.assertIn('1.0.18', title)
        self.assertIn('Web', title)
        self.assertIn('1.0.18', message)

    def test_detail_is_appended(self):
        notify.notify_release('Web', '1.0.18', 'Live at https://roadmate.club.',
                              send=self.record)
        self.assertIn('roadmate.club', self.sent[0][1])

    def test_each_platform_gets_its_own_alert(self):
        for platform in ('Web', 'Android', 'iOS'):
            notify.notify_release(platform, '1.0.18', send=self.record)
        self.assertEqual([t for t, _ in self.sent],
                         ['RoadMate Web release: v1.0.18',
                          'RoadMate Android release: v1.0.18',
                          'RoadMate iOS release: v1.0.18'])

    def test_store_alerts_must_not_claim_users_have_it(self):
        """Committed/submitted is NOT live (the 0.1.72 lesson) — the caveat
        travels in `detail`, so the alert can never be misread."""
        notify.notify_release('Android', '1.0.18',
                              'Committed to the Google Play production track. '
                              'NOT live yet: Play review must pass.',
                              send=self.record)
        self.assertIn('NOT live yet', self.sent[0][1])


if __name__ == '__main__':
    unittest.main(verbosity=1)
