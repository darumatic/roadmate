#!/usr/bin/env python3
"""RoadMate's unofficial Firestore read meter — the alerting half (issue #54).

The Firebase project has no billing account, so the 50,000 reads/day quota is
a cliff: past it Firestore *refuses* reads until the daily reset (midnight
Pacific, ~5-6 pm AEST) — an outage, not a bill. The same fact blocks measuring
it: Google's metrics API answers "requires billing to be enabled". So metered
builds of the app count what Firestore delivers to them and add it to one
counter document a day, ``usage/<quota day>`` (``lib/services/read_meter.dart``),
and this script — an hourly cron on the VPS — reads that one document and
pushes **one ntfy alert per quota day**, the first time the count reaches the
threshold (35,000 = 70 %).

It is a floor, not the true figure: builds without the meter are invisible,
reads made inside security rules can't be seen by the app, console browsing
isn't counted. The nightly backup adds its own reads, which it knows exactly
(``backup_server``), and this script adds its own here — one a run.

Stdlib only; the Admin service account and the REST client are
``backup_firestore.py``'s.

Usage
  scripts/read_meter.py                 # check, alert if due, print a summary
  scripts/read_meter.py --quiet         # cron: print only when alerting
  scripts/read_meter.py --dry-run       # never alert, never touch the state
  scripts/read_meter.py --self-test     # offline unit tests
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
import zoneinfo

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

DAILY_QUOTA = 50_000
ALERT_AT = 35_000

# Firestore's daily quotas reset at midnight Pacific time.
QUOTA_ZONE = zoneinfo.ZoneInfo('America/Los_Angeles')

COLLECTION = 'usage'
# Set by the server side, never by an app build (firestore.rules holds
# clients to that): the nightly backup's own reads.
BACKUP_FIELD = 'backup_server'

DEFAULT_STATE_FILE = os.path.expanduser(
    '~/.local/state/roadmate/read_meter.json')


# --------------------------------------------------------------------------
# Pure helpers (unit-tested in read_meter_test.py)
# --------------------------------------------------------------------------

def quota_day(moment: dt.datetime) -> str:
    """The quota day ``moment`` falls in — the id of that day's counter doc.

    Must agree with ``quotaDayOf`` in lib/services/read_meter.dart, which has
    no zone database and applies the US rules by hand; the Dart suite runs
    this function against it (test/read_meter_script_test.dart).
    """
    if moment.tzinfo is None:
        raise ValueError('quota_day needs an aware datetime')
    return moment.astimezone(QUOTA_ZONE).date().isoformat()


def counters(fields) -> dict:
    """The integer counters of a REST ``fields`` payload, by name."""
    out = {}
    for name, value in (fields or {}).items():
        if 'integerValue' in value:
            out[name] = int(value['integerValue'])
    return out


def breakdown(counts: dict) -> str:
    """"sites 28,100 · reports 5,300 · …" — biggest first, zeros dropped.

    Counter names are ``<source>_<platform>``; the alert sums by source and
    then by platform, because "where do the reads go" has both answers.
    """
    def summed(index):
        totals = {}
        for name, reads in counts.items():
            parts = name.rsplit('_', 1)
            key = parts[index] if len(parts) == 2 else name
            totals[key] = totals.get(key, 0) + reads
        ranked = sorted(totals.items(), key=lambda kv: (-kv[1], kv[0]))
        return ' · '.join(f'{key} {reads:,}' for key, reads in ranked if reads)

    by_source, by_platform = summed(0), summed(1)
    if not by_source:
        return 'nothing counted yet'
    return f'{by_source} — {by_platform}'


def should_alert(total: int, day: str, state: dict,
                 threshold: int = ALERT_AT) -> bool:
    """Once per quota day, the first time the count reaches the threshold."""
    return total >= threshold and state.get('alertedDay') != day


def alert_text(total: int, day: str, counts: dict,
               threshold: int = ALERT_AT, quota: int = DAILY_QUOTA):
    title = f'RoadMate: {total:,} Firestore reads today ({total * 100 // quota}%)'
    message = (
        f'At least {total:,} of the {quota:,} daily reads are used (quota day '
        f'{day}, resets at midnight Pacific). Past {quota:,} Firestore '
        f'REFUSES reads until the reset. Counted: {breakdown(counts)}. '
        'This is a floor — unmetered builds, rules lookups and console '
        'browsing are not in it.')
    return title, message


# --------------------------------------------------------------------------
# State: what this script has to remember between runs
# --------------------------------------------------------------------------

def load_state(path: str) -> dict:
    try:
        with open(path) as handle:
            state = json.load(handle)
        return state if isinstance(state, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(path: str, state: dict) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + '.partial'
    with open(tmp, 'w') as handle:
        json.dump(state, handle)
    os.replace(tmp, path)


def own_reads(state: dict, day: str) -> int:
    """How many reads this script has made in ``day``, this run included."""
    runs = state.get('runs') or {}
    return int(runs.get(day, 0)) + 1


# --------------------------------------------------------------------------
# The check
# --------------------------------------------------------------------------

def check(client, now: dt.datetime, state: dict, send,
          threshold: int = ALERT_AT, dry_run: bool = False):
    """Reads the day's counter document, alerts if due, and returns
    ``(total, counts, alerted, new_state)``."""
    day = quota_day(now)
    document = client.get_document(f'{COLLECTION}/{day}')
    counts = counters((document or {}).get('fields'))
    mine = own_reads(state, day)
    counts['meter_server'] = mine
    total = sum(counts.values())

    # Only the current day is worth remembering.
    new_state = {'runs': {day: mine}, 'alertedDay': state.get('alertedDay')}
    alerted = False
    if should_alert(total, day, state, threshold) and not dry_run:
        title, message = alert_text(total, day, counts, threshold)
        # Marked as sent only when it was: an alert that could not be
        # delivered is retried on the next run rather than lost for the day.
        if send(title, message, priority='high'):
            new_state['alertedDay'] = day
            alerted = True
    return total, counts, alerted, new_state


def build_parser():
    from backup_firestore import DEFAULT_KEY_FILE  # noqa: PLC0415
    parser = argparse.ArgumentParser(
        description="RoadMate's unofficial Firestore read meter (issue #54).")
    parser.add_argument('--key-file', default=DEFAULT_KEY_FILE)
    parser.add_argument('--state-file', default=DEFAULT_STATE_FILE)
    parser.add_argument('--threshold', type=int, default=ALERT_AT)
    parser.add_argument('--quiet', action='store_true',
                        help='print only when an alert goes out')
    parser.add_argument('--dry-run', action='store_true',
                        help='never alert and never touch the state file')
    parser.add_argument('--self-test', action='store_true')
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    if args.self_test:
        import unittest  # noqa: PLC0415
        import read_meter_test  # noqa: PLC0415
        suite = unittest.defaultTestLoader.loadTestsFromModule(read_meter_test)
        return 0 if unittest.TextTestRunner().run(suite).wasSuccessful() else 1

    from backup_firestore import Firestore  # noqa: PLC0415
    from notify import send  # noqa: PLC0415

    now = dt.datetime.now(dt.timezone.utc)
    state = load_state(args.state_file)
    total, counts, alerted, new_state = check(
        Firestore(args.key_file), now, state, send,
        threshold=args.threshold, dry_run=args.dry_run)
    if not args.dry_run:
        save_state(args.state_file, new_state)
    if alerted or not args.quiet:
        stamp = now.isoformat(timespec='seconds')
        print(f'[{stamp}] quota day {quota_day(now)}: at least {total:,} '
              f'read(s), {total * 100 // DAILY_QUOTA}% of {DAILY_QUOTA:,} — '
              f'{breakdown(counts)}{" — ALERT SENT" if alerted else ""}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
