#!/usr/bin/env python3
"""Offline unit tests for scripts/read_meter.py.

Run directly (``python3 scripts/read_meter_test.py``), via
``scripts/read_meter.py --self-test``, or as part of ``flutter test`` through
``test/read_meter_script_test.dart``. No network, no credentials.
"""

import datetime as dt
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import read_meter as rm  # noqa: E402

UTC = dt.timezone.utc


def fields(**counts):
    """A REST ``fields`` payload, as Firestore returns the counter doc."""
    out = {name: {'integerValue': str(n)} for name, n in counts.items()}
    out['updatedAt'] = {'timestampValue': '2026-09-21T03:00:00Z'}
    return out


class FakeClient:
    def __init__(self, document):
        self.document = document
        self.paths = []

    def get_document(self, path):
        self.paths.append(path)
        return self.document


class Alerts:
    def __init__(self, delivered=True):
        self.delivered = delivered
        self.sent = []

    def __call__(self, title, message, priority=None):
        self.sent.append((title, message, priority))
        return self.delivered


class QuotaDayTest(unittest.TestCase):
    """Firestore's daily quota resets at midnight Pacific time, so that is the
    day to count in. lib/services/read_meter.dart applies the US daylight
    rules by hand; test/read_meter_script_test.dart holds it to this."""

    def test_winter_days_turn_over_at_0800_utc(self):
        self.assertEqual(
            rm.quota_day(dt.datetime(2026, 1, 15, 7, 59, tzinfo=UTC)),
            '2026-01-14')
        self.assertEqual(
            rm.quota_day(dt.datetime(2026, 1, 15, 8, 0, tzinfo=UTC)),
            '2026-01-15')

    def test_summer_days_turn_over_at_0700_utc(self):
        self.assertEqual(
            rm.quota_day(dt.datetime(2026, 7, 1, 6, 59, tzinfo=UTC)),
            '2026-06-30')
        self.assertEqual(
            rm.quota_day(dt.datetime(2026, 7, 1, 7, 0, tzinfo=UTC)),
            '2026-07-01')

    def test_the_nightly_backup_at_3am_aest_is_still_yesterday_there(self):
        aest = dt.timezone(dt.timedelta(hours=10))
        self.assertEqual(
            rm.quota_day(dt.datetime(2026, 9, 22, 3, 0, tzinfo=aest)),
            '2026-09-21')

    def test_a_naive_datetime_is_refused(self):
        with self.assertRaises(ValueError):
            rm.quota_day(dt.datetime(2026, 9, 21, 3, 0))


class CountersTest(unittest.TestCase):
    def test_only_integer_fields_count(self):
        self.assertEqual(
            rm.counters(fields(sites_web=89, reports_web=14)),
            {'sites_web': 89, 'reports_web': 14})

    def test_a_missing_document_counts_nothing(self):
        self.assertEqual(rm.counters(None), {})
        self.assertEqual(rm.counters({}), {})

    def test_breakdown_says_where_the_reads_go_by_source_then_platform(self):
        text = rm.breakdown({'sites_web': 20000, 'sites_android': 8100,
                             'reports_web': 5300, 'other_ios': 0,
                             'backup_server': 520})
        self.assertEqual(
            text,
            'sites 28,100 · reports 5,300 · backup 520 — '
            'web 25,300 · android 8,100 · server 520')

    def test_breakdown_of_nothing(self):
        self.assertEqual(rm.breakdown({}), 'nothing counted yet')


class CheckTest(unittest.TestCase):
    NOW = dt.datetime(2026, 9, 21, 3, 0, tzinfo=UTC)  # quota day 2026-09-20

    def test_reads_the_one_document_of_the_quota_day(self):
        client = FakeClient({'fields': fields(sites_web=100)})
        total, counts, alerted, _ = rm.check(client, self.NOW, {}, Alerts())
        self.assertEqual(client.paths, ['usage/2026-09-20'])
        # Its own read is part of the day too.
        self.assertEqual(counts, {'sites_web': 100, 'meter_server': 1})
        self.assertEqual(total, 101)
        self.assertFalse(alerted)

    def test_no_document_yet_is_a_quiet_day_not_an_error(self):
        total, _, alerted, _ = rm.check(
            FakeClient(None), self.NOW, {}, Alerts())
        self.assertEqual(total, 1)
        self.assertFalse(alerted)

    def test_alerts_the_first_time_the_count_reaches_the_threshold(self):
        alerts = Alerts()
        client = FakeClient({'fields': fields(sites_web=30000,
                                              reports_web=4999)})
        _, _, alerted, state = rm.check(client, self.NOW, {}, alerts)
        self.assertTrue(alerted)
        self.assertEqual(state['alertedDay'], '2026-09-20')
        (title, message, priority), = alerts.sent
        self.assertEqual(priority, 'high')
        self.assertIn('35,000', title)
        self.assertIn('70%', title)
        self.assertIn('REFUSES reads', message)
        self.assertIn('sites 30,000', message)
        self.assertIn('floor', message)
        # An HTTP header: ntfy titles must stay latin-1.
        title.encode('latin-1')

    def test_and_only_once_per_quota_day(self):
        alerts = Alerts()
        client = FakeClient({'fields': fields(sites_web=40000)})
        _, _, first, state = rm.check(client, self.NOW, {}, alerts)
        _, _, again, state = rm.check(
            client, self.NOW + dt.timedelta(hours=1), state, alerts)
        self.assertTrue(first)
        self.assertFalse(again)
        self.assertEqual(len(alerts.sent), 1)

    def test_a_new_quota_day_can_alert_again(self):
        alerts = Alerts()
        client = FakeClient({'fields': fields(sites_web=40000)})
        _, _, _, state = rm.check(client, self.NOW, {}, alerts)
        _, _, again, _ = rm.check(
            client, self.NOW + dt.timedelta(days=1), state, alerts)
        self.assertTrue(again)
        self.assertEqual(len(alerts.sent), 2)

    def test_an_alert_that_could_not_be_delivered_is_retried_next_run(self):
        client = FakeClient({'fields': fields(sites_web=40000)})
        _, _, alerted, state = rm.check(
            client, self.NOW, {}, Alerts(delivered=False))
        self.assertFalse(alerted)
        self.assertIsNone(state['alertedDay'])
        alerts = Alerts()
        _, _, alerted, _ = rm.check(
            client, self.NOW + dt.timedelta(hours=1), state, alerts)
        self.assertTrue(alerted)

    def test_a_dry_run_never_alerts(self):
        alerts = Alerts()
        client = FakeClient({'fields': fields(sites_web=40000)})
        _, _, alerted, _ = rm.check(client, self.NOW, {}, alerts,
                                    dry_run=True)
        self.assertFalse(alerted)
        self.assertEqual(alerts.sent, [])

    def test_its_own_reads_add_up_over_the_day_and_start_again_with_it(self):
        client = FakeClient(None)
        state = {}
        for hour in range(3):
            total, _, _, state = rm.check(
                client, self.NOW + dt.timedelta(hours=hour), state, Alerts())
        self.assertEqual(total, 3)
        total, _, _, state = rm.check(
            client, self.NOW + dt.timedelta(days=1), state, Alerts())
        self.assertEqual(total, 1)
        self.assertEqual(list(state['runs']), ['2026-09-21'])


class StateTest(unittest.TestCase):
    def test_round_trips_and_creates_its_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, 'state', 'roadmate', 'read_meter.json')
            rm.save_state(path, {'alertedDay': '2026-09-20',
                                 'runs': {'2026-09-20': 4}})
            self.assertEqual(rm.load_state(path)['runs'], {'2026-09-20': 4})
            self.assertFalse(os.path.exists(path + '.partial'))

    def test_a_missing_or_mangled_file_is_a_fresh_start(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, 'read_meter.json')
            self.assertEqual(rm.load_state(path), {})
            with open(path, 'w') as handle:
                handle.write('{not json')
            self.assertEqual(rm.load_state(path), {})
            with open(path, 'w') as handle:
                json.dump(['a', 'list'], handle)
            self.assertEqual(rm.load_state(path), {})


class ConstantsTest(unittest.TestCase):
    def test_the_alert_is_at_70_percent_of_the_quota(self):
        self.assertEqual(rm.DAILY_QUOTA, 50_000)
        self.assertEqual(rm.ALERT_AT, 35_000)
        self.assertEqual(rm.ALERT_AT * 100 // rm.DAILY_QUOTA, 70)


if __name__ == '__main__':
    unittest.main()
