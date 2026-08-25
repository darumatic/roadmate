#!/usr/bin/env python3
"""Push an attention alert to the owner via ntfy.sh.

Usage:
  notify.py <title> <message...>   send one alert
  notify.py --test                 send a test alert and report the outcome

The secret topic name is read from ``~/.config/roadmate/ntfy_topic`` (one
line, chmod 600; treat it like a password — anyone who knows it can read and
post alerts). The owner subscribes to it in the ntfy app or at
https://ntfy.sh/<topic>. An unconfigured or empty topic file makes every send
a silent no-op, so callers never break.

Why this channel exists: the auto-fixer and the backup cron act with the
owner's own GitHub token, and GitHub sends no notifications for your own
activity — so issue comments alone would go unseen. Used by the backup
crontab lines (``|| notify.py …``) and by fix_issues.py for every terminal
outcome. Alerts must never crash a caller: send() swallows network errors.
"""

import os
import sys
import urllib.error
import urllib.request

TOPIC_FILE = os.path.expanduser('~/.config/roadmate/ntfy_topic')
NTFY_ROOT = 'https://ntfy.sh'


def read_topic(path=None):
    path = TOPIC_FILE if path is None else path
    try:
        with open(path) as handle:
            topic = handle.read().strip()
    except OSError:
        return None
    return topic or None


def send(title, message, topic=None, urlopen=urllib.request.urlopen):
    """Post one notification. True = delivered; False = skipped or failed."""
    topic = topic or read_topic()
    if not topic:
        return False
    request = urllib.request.Request(
        '%s/%s' % (NTFY_ROOT, topic),
        data=message.encode('utf-8'),
        headers={'Title': title, 'Tags': 'rotating_light'})
    try:
        with urlopen(request, timeout=15) as response:
            return 200 <= response.status < 300
    except (urllib.error.URLError, OSError):
        return False


def main(argv):
    if len(argv) >= 1 and argv[0] == '--test':
        if read_topic() is None:
            print('notify: no topic configured at %s' % TOPIC_FILE)
            return 2
        ok = send('RoadMate alerts test', 'If you can read this, alerts work.')
        print('notify: test %s' % ('sent' if ok else 'FAILED (network?)'))
        return 0 if ok else 1
    if not argv:
        print(__doc__)
        return 2
    title = argv[0]
    message = ' '.join(argv[1:]) or title
    return 0 if send(title, message) else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
