#!/usr/bin/env python3
"""RoadMate Firestore backup / restore — disaster recovery.

The live Firestore database at ``roadmate-b1551`` is the only copy of every
community report. ``firestore.rules`` deliberately forbids client-side
re-seeding, so a wiped or corrupted database cannot be rebuilt from the app —
recovery depends entirely on a snapshot taken beforehand. This script takes
that snapshot.

Stdlib only (matching ``play_upload.py`` / ``asc_submit.py``): the service
account JWT is signed with ES256/RS256 via the ``openssl`` CLI, so there is
nothing to ``pip install`` on the VPS.

Backup
  Walks every collection recursively (root collections, then each document's
  subcollections) and writes a gzipped JSON snapshot to ``~/backups``. Document
  bodies are stored as the raw Firestore REST ``fields`` payload, so timestamps,
  geopoints, integers and references all survive a round trip byte-for-byte.

Read cost
  A full backup bills one document read per document (~1,100 today, ~2% of the
  50k/day free tier) and ``reports`` are ~80% of that, growing without bound.
  ``--incremental`` carries reports forward from the newest snapshot and fetches
  only those at or after its watermark, cutting a run to ~260 reads. Reports are
  append-only under ``firestore.rules`` — users may only create them — so this
  is safe for the shapes clients produce.

  Admins *can* edit and delete reports, so every run cross-checks its totals
  against server-side ``count()`` aggregations (~7 reads): a deletion changes
  the count and the run automatically re-reads in full. An admin *edit* leaves
  the count unchanged and would go unnoticed, which is why cron still takes a
  full backup weekly (Sunday) alongside the nightly incrementals.

Restore
  ``--restore <snapshot>`` writes the documents back through the Admin service
  account, which bypasses security rules. It is a **dry run by default** and
  needs an explicit ``--confirm`` to touch the live database. Restore upserts:
  it recreates missing documents and overwrites existing ones, but never
  deletes documents that are absent from the snapshot.

Usage
  scripts/backup_firestore.py                       # full snapshot -> ~/backups
  scripts/backup_firestore.py --incremental         # cheap run (see Read cost)
  scripts/backup_firestore.py --out-dir /mnt/dr
  scripts/backup_firestore.py --keep 30             # retention (0 = keep all)
  scripts/backup_firestore.py --restore ~/backups/roadmate-....json.gz
  scripts/backup_firestore.py --restore <file> --confirm
  scripts/backup_firestore.py --self-test           # offline unit tests
"""

from __future__ import annotations

import argparse
import base64
import concurrent.futures
import datetime as dt
import gzip
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

DEFAULT_KEY_FILE = os.path.expanduser(
    '~/.config/roadmate/firebase-adminsdk.json')
DEFAULT_OUT_DIR = os.path.expanduser('~/backups')
DEFAULT_KEEP = 30

FILE_PREFIX = 'roadmate-firestore-'
FILE_SUFFIX = '.json.gz'
FORMAT_VERSION = 1

# Firestore caps a commit at 500 writes.
COMMIT_BATCH_SIZE = 400
PAGE_SIZE = 300
# Parallel subcollection probes during the walk (one round trip per document).
WALK_WORKERS = 16
# The append-only collection an incremental run carries forward instead of
# re-reading. Reports are ~80% of the database and grow without bound.
INCREMENTAL_COLLECTION = 'reports'
INCREMENTAL_TIMESTAMP_FIELD = 'createdAt'


# --------------------------------------------------------------------------
# Pure helpers (covered by --self-test; no network, no credentials)
# --------------------------------------------------------------------------

def snapshot_filename(when: dt.datetime) -> str:
    """Timestamped name whose lexicographic order matches chronological order."""
    return f'{FILE_PREFIX}{when.strftime("%Y%m%d-%H%M%S")}{FILE_SUFFIX}'


def is_snapshot_name(name: str) -> bool:
    return name.startswith(FILE_PREFIX) and name.endswith(FILE_SUFFIX)


def snapshots_to_prune(names, keep: int):
    """Snapshot files to delete so only the newest ``keep`` remain.

    ``keep <= 0`` disables pruning. Non-snapshot files in the directory are
    never returned — the output directory may hold unrelated backups.
    """
    if keep <= 0:
        return []
    snaps = sorted((n for n in names if is_snapshot_name(n)), reverse=True)
    return sorted(snaps[keep:])


def relative_path(name: str) -> str:
    """``projects/p/databases/(default)/documents/sites/x`` -> ``sites/x``."""
    marker = '/documents/'
    idx = name.find(marker)
    if idx == -1:
        raise ValueError(f'not a Firestore document name: {name!r}')
    return name[idx + len(marker):]


def document_name(project: str, database: str, path: str) -> str:
    return (f'projects/{project}/databases/{database}/documents/'
            f'{path}')


def url_path(rel_path: str) -> str:
    """Percent-encode a relative document/collection path for a REST URL.

    Document IDs are user-chosen — a ``usernames`` key can be ``big trucker``
    — and raw interpolation of a space into the URL raises InvalidURL, which
    silently killed every nightly backup from 2026-08-05 until 2026-08-25.
    Only the segment contents are encoded; ``/`` separators are kept.
    """
    return urllib.parse.quote(rel_path, safe='/')


def count_by_collection_id(records):
    """Walked document totals per collection id, for the count() cross-check.

    Placeholder parents are excluded: a document that exists only because it
    has a subcollection is not a document as far as ``count()`` is concerned
    (RoadMate has ~45 of these under ``users`` — uids with favourites but no
    profile doc), and counting them would make every run report a false drop.
    """
    totals = {}
    for record in records:
        if record.get('missing'):
            continue
        totals.setdefault(record['path'].split('/')[-2], 0)
        totals[record['path'].split('/')[-2]] += 1
    return totals


def compare_counts(walked, server):
    """Collection ids where the walk and the server's count() disagree.

    Returns ``{id: (walked, server)}``. A live database mutates during a walk,
    so a mismatch is a warning, not a failure — but a silent drop would show up
    here rather than being discovered at restore time.
    """
    return {cid: (walked.get(cid, 0), server[cid])
            for cid in server
            if walked.get(cid, 0) != server[cid]}


def newest_snapshot(names):
    """The most recent snapshot filename, or None."""
    snaps = sorted(n for n in names if is_snapshot_name(n))
    return snaps[-1] if snaps else None


def report_watermark(documents):
    """Latest ``createdAt`` among backed-up reports, or None.

    Reports are append-only under ``firestore.rules`` (users may only create
    them; edits and deletes are admin-only), so everything at or before this
    timestamp is already captured and never needs re-reading.
    """
    stamps = [
        d['fields']['createdAt']['timestampValue']
        for d in documents
        if d['path'].split('/')[-2] == INCREMENTAL_COLLECTION
        and not d.get('missing')
        and 'createdAt' in d.get('fields', {})
        and 'timestampValue' in d['fields']['createdAt']
    ]
    return max(stamps) if stamps else None


def merge_documents(carried, fresh):
    """Carried-forward documents overlaid with freshly fetched ones."""
    merged = {d['path']: d for d in carried}
    merged.update({d['path']: d for d in fresh})
    return [merged[p] for p in sorted(merged)]


def carried_reports(documents):
    return [d for d in documents
            if d['path'].split('/')[-2] == INCREMENTAL_COLLECTION]


def collection_ids(paths):
    """Distinct collection ids (every odd path segment) in a snapshot."""
    ids = set()
    for p in paths:
        segments = p.split('/')
        for i in range(0, len(segments), 2):
            ids.add(segments[i])
    return sorted(ids)


def validate_snapshot(snapshot) -> None:
    """Reject anything that is not a snapshot this script produced."""
    if not isinstance(snapshot, dict):
        raise ValueError('snapshot is not a JSON object')
    if snapshot.get('formatVersion') != FORMAT_VERSION:
        raise ValueError(
            f'unsupported formatVersion {snapshot.get("formatVersion")!r} '
            f'(expected {FORMAT_VERSION})')
    docs = snapshot.get('documents')
    if not isinstance(docs, list):
        raise ValueError('snapshot has no "documents" list')
    for doc in docs:
        if not isinstance(doc, dict) or not doc.get('path'):
            raise ValueError('snapshot contains a document without a path')
        if len(str(doc['path']).split('/')) % 2 != 0:
            raise ValueError(
                f'document path is not collection/doc pairs: {doc["path"]!r}')


def restore_writes(snapshot, project: str, database: str):
    """Firestore ``commit`` write ops for a snapshot.

    Documents recorded as *missing* (path placeholders that only ever existed
    as parents of a subcollection) carry no data and are skipped — writing them
    would materialise documents that never existed.
    """
    writes = []
    for doc in snapshot['documents']:
        if doc.get('missing'):
            continue
        writes.append({'update': {
            'name': document_name(project, database, doc['path']),
            'fields': doc.get('fields', {}),
        }})
    return writes


def chunks(items, size):
    for i in range(0, len(items), size):
        yield items[i:i + size]


def human_size(num_bytes: int) -> str:
    value = float(num_bytes)
    for unit in ('B', 'KB', 'MB', 'GB'):
        if value < 1024 or unit == 'GB':
            return f'{value:.0f} {unit}' if unit == 'B' else f'{value:.1f} {unit}'
        value /= 1024
    return f'{value:.1f} GB'


# --------------------------------------------------------------------------
# Google auth + Firestore REST
# --------------------------------------------------------------------------

def _b64url(raw: bytes) -> bytes:
    return base64.urlsafe_b64encode(raw).rstrip(b'=')


class Firestore:
    """Minimal Firestore REST client authenticated as the Admin SA."""

    def __init__(self, key_file: str, database: str = '(default)'):
        with open(key_file) as fh:
            self.sa = json.load(fh)
        self.project = self.sa['project_id']
        self.database = database
        self.root = (f'https://firestore.googleapis.com/v1/projects/'
                     f'{self.project}/databases/{database}/documents')
        self._token = None
        self._token_expiry = 0.0
        self._token_lock = threading.Lock()

    # -- auth ------------------------------------------------------------
    def _sign(self, payload: bytes) -> bytes:
        with tempfile.NamedTemporaryFile('w', suffix='.pem',
                                         delete=False) as fh:
            fh.write(self.sa['private_key'])
            key_path = fh.name
        try:
            proc = subprocess.run(
                ['openssl', 'dgst', '-sha256', '-sign', key_path, '-binary'],
                input=payload, capture_output=True, check=True)
        finally:
            os.unlink(key_path)
        return proc.stdout

    def token(self) -> str:
        # The walk probes subcollections from a thread pool; mint once.
        with self._token_lock:
            if self._token and time.time() < self._token_expiry - 60:
                return self._token
            return self._mint_token()

    def _mint_token(self) -> str:
        now = int(time.time())
        header = _b64url(json.dumps({'alg': 'RS256', 'typ': 'JWT'}).encode())
        claims = _b64url(json.dumps({
            'iss': self.sa['client_email'],
            'scope': 'https://www.googleapis.com/auth/datastore',
            'aud': self.sa['token_uri'],
            'iat': now,
            'exp': now + 3600,
        }).encode())
        signing_input = header + b'.' + claims
        jwt = signing_input + b'.' + _b64url(self._sign(signing_input))
        body = urllib.parse.urlencode({
            'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion': jwt.decode(),
        }).encode()
        resp = self._raw(urllib.request.Request(self.sa['token_uri'],
                                                data=body))
        self._token = resp['access_token']
        self._token_expiry = time.time() + int(resp.get('expires_in', 3600))
        return self._token

    # -- transport -------------------------------------------------------
    @staticmethod
    def _raw(req, attempts: int = 4):
        last = None
        for attempt in range(attempts):
            try:
                with urllib.request.urlopen(req, timeout=120) as resp:
                    return json.loads(resp.read().decode() or '{}')
            except urllib.error.HTTPError as err:
                detail = err.read().decode(errors='replace')[:500]
                # 429/5xx are transient; 4xx otherwise is a real error.
                if err.code != 429 and err.code < 500:
                    raise RuntimeError(
                        f'{err.code} {err.reason} for {req.full_url}\n'
                        f'{detail}') from None
                last = RuntimeError(f'{err.code} {err.reason}: {detail}')
            except urllib.error.URLError as err:
                last = RuntimeError(str(err))
            time.sleep(2 ** attempt)
        raise last

    def _call(self, url: str, payload=None):
        data = None if payload is None else json.dumps(payload).encode()
        headers = {'Authorization': f'Bearer {self.token()}'}
        if data is not None:
            headers['Content-Type'] = 'application/json'
        return self._raw(urllib.request.Request(url, data=data,
                                                headers=headers))

    # -- operations ------------------------------------------------------
    def list_collection_ids(self, parent_path: str = ''):
        url = (f'{self.root}/{url_path(parent_path)}:listCollectionIds'
               if parent_path else f'{self.root}:listCollectionIds')
        ids, page_token = [], None
        while True:
            payload = {'pageSize': 100}
            if page_token:
                payload['pageToken'] = page_token
            resp = self._call(url, payload)
            ids.extend(resp.get('collectionIds', []))
            page_token = resp.get('nextPageToken')
            if not page_token:
                return ids

    def list_documents(self, parent_path: str, collection_id: str):
        """All documents in a collection, including 'missing' parent docs."""
        base = (f'{self.root}/{url_path(parent_path)}/{url_path(collection_id)}'
                if parent_path else f'{self.root}/{url_path(collection_id)}')
        page_token, docs = None, []
        while True:
            params = {'pageSize': PAGE_SIZE, 'showMissing': 'true'}
            if page_token:
                params['pageToken'] = page_token
            resp = self._call(f'{base}?{urllib.parse.urlencode(params)}')
            docs.extend(resp.get('documents', []))
            page_token = resp.get('nextPageToken')
            if not page_token:
                return docs

    def count(self, collection_id: str, all_descendants: bool = True) -> int:
        """count() aggregation — one read per 1000 index entries scanned."""
        resp = self._call(f'{self.root}:runAggregationQuery', {
            'structuredAggregationQuery': {
                'structuredQuery': {'from': [{
                    'collectionId': collection_id,
                    'allDescendants': all_descendants}]},
                'aggregations': [{'alias': 'n', 'count': {}}]}})
        return int(resp[0]['result']['aggregateFields']['n']['integerValue'])

    def query_since(self, collection_id: str, field: str, timestamp: str):
        """Collection-group documents with ``field >= timestamp``.

        ``>=`` rather than ``>`` so a report sharing the watermark's exact
        timestamp cannot slip through the gap; duplicates are deduped on merge.
        """
        resp = self._call(f'{self.root}:runQuery', {'structuredQuery': {
            'from': [{'collectionId': collection_id, 'allDescendants': True}],
            'where': {'fieldFilter': {
                'field': {'fieldPath': field},
                'op': 'GREATER_THAN_OR_EQUAL',
                'value': {'timestampValue': timestamp}}},
            'orderBy': [{'field': {'fieldPath': field},
                         'direction': 'ASCENDING'}],
        }})
        return [row['document'] for row in resp if 'document' in row]

    def commit(self, writes):
        return self._call(f'{self.root}:commit', {'writes': writes})


# --------------------------------------------------------------------------
# Backup
# --------------------------------------------------------------------------

def to_record(doc):
    """A Firestore REST document as stored in a snapshot."""
    record = {'path': relative_path(doc['name'])}
    if 'fields' in doc or 'createTime' in doc:
        # Raw REST fields: timestamps, geopoints and int64s round trip exactly.
        record['fields'] = doc.get('fields', {})
        record['createTime'] = doc.get('createTime')
        record['updateTime'] = doc.get('updateTime')
    else:
        # Present only as the parent of a subcollection; has no data of its own.
        record['missing'] = True
    return record


def walk(client, verbose: bool = True, workers: int = WALK_WORKERS,
         skip: frozenset = frozenset()):
    """Every document in the database, breadth-first by depth level.

    Discovering subcollections costs one ``listCollectionIds`` round trip per
    document — over a thousand of them here, and growing with every report. Each
    depth level is therefore fanned out across a thread pool; run serially this
    takes minutes, which is too slow to stay honest as the database grows.

    ``skip`` names collection ids not to descend into; incremental runs skip
    ``reports`` and fetch only the new ones instead.
    """
    out = []
    level = [('', cid) for cid in client.list_collection_ids('')
             if cid not in skip]
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        while level:
            listings = list(pool.map(
                lambda pc: (pc, client.list_documents(*pc)), level))
            paths = []
            for (parent, collection_id), docs in listings:
                label = f'{parent}/{collection_id}' if parent else collection_id
                if verbose:
                    print(f'  {label}: {len(docs)} doc(s)', flush=True)
                for doc in docs:
                    record = to_record(doc)
                    out.append(record)
                    paths.append(record['path'])
            level = [(path, sub)
                     for path, subs in zip(
                         paths, pool.map(client.list_collection_ids, paths))
                     for sub in subs if sub not in skip]
    return out


def do_backup(args) -> int:
    client = Firestore(args.key_file)
    stamp = dt.datetime.now().isoformat(timespec='seconds')
    print(f'[{stamp}] Backing up {client.project} {client.database} ...')
    started = time.time()

    base, watermark = None, None
    if args.incremental:
        latest = newest_snapshot(os.listdir(args.out_dir)
                                 if os.path.isdir(args.out_dir) else [])
        if latest:
            base = load_snapshot(os.path.join(args.out_dir, latest))
            watermark = report_watermark(base['documents'])
        if watermark is None:
            print('  no usable base snapshot — falling back to a full backup')

    mode = 'incremental' if watermark else 'full'
    if watermark:
        # Skip re-reading every historical report; fetch only what is new.
        documents = walk(client, verbose=not args.quiet,
                         skip=frozenset([INCREMENTAL_COLLECTION]))
        fresh = [to_record(d) for d in client.query_since(
            INCREMENTAL_COLLECTION, INCREMENTAL_TIMESTAMP_FIELD, watermark)]
        carried = carried_reports(base['documents'])
        documents = merge_documents(carried + documents, fresh)
        print(f'  carried forward {len(carried)} report(s) from '
              f'{base["createdAt"]}; fetched {len(fresh)} at/after {watermark}')
    else:
        documents = walk(client, verbose=not args.quiet)

    # Cross-check the walk against the server's own count(). Costs ~1 read per
    # collection id and turns a silent drop into a visible warning; without it
    # a truncated backup only reveals itself during a restore.
    walked = count_by_collection_id(documents)
    mismatches = {}
    if not args.no_verify:
        server = {cid: client.count(cid) for cid in walked}
        mismatches = compare_counts(walked, server)

        # An incremental run carries reports forward on the assumption they are
        # append-only. Admins *can* delete or edit them, so when the carried
        # total disagrees with the server, re-read the collection in full: one
        # cheap count() buys the guarantee that cheap runs stay correct.
        if mode == 'incremental' and INCREMENTAL_COLLECTION in mismatches:
            got, expected = mismatches[INCREMENTAL_COLLECTION]
            print(f'  {INCREMENTAL_COLLECTION}: carried {got}, server has '
                  f'{expected} — re-reading in full', flush=True)
            documents = walk(client, verbose=not args.quiet)
            mode = 'full (incremental repaired)'
            walked = count_by_collection_id(documents)
            server = {cid: client.count(cid) for cid in walked}
            mismatches = compare_counts(walked, server)

        for cid, (got, expected) in sorted(mismatches.items()):
            print(f'  WARNING: {cid}: backed up {got}, server counts '
                  f'{expected} (concurrent write, or a dropped document)',
                  file=sys.stderr)

    snapshot = {
        'formatVersion': FORMAT_VERSION,
        'tool': 'scripts/backup_firestore.py',
        'project': client.project,
        'database': client.database,
        'createdAt': dt.datetime.now(dt.timezone.utc).isoformat(
            timespec='seconds').replace('+00:00', 'Z'),
        'documentCount': len(documents),
        'mode': mode,
        'basedOn': base['createdAt'] if watermark else None,
        'collections': collection_ids(d['path'] for d in documents),
        'countsByCollectionId': walked,
        'verified': not args.no_verify and not mismatches,
        'documents': documents,
    }

    os.makedirs(args.out_dir, exist_ok=True)
    target = os.path.join(args.out_dir,
                          snapshot_filename(dt.datetime.now()))
    tmp = target + '.partial'
    # Write to a .partial first so an interrupted run never leaves behind a
    # truncated file that looks like a usable backup.
    with gzip.open(tmp, 'wt', encoding='utf-8') as fh:
        json.dump(snapshot, fh, ensure_ascii=False)
    os.replace(tmp, target)

    size = os.path.getsize(target)
    print(f'\nWrote {len(documents)} documents ({mode}) to {target} '
          f'({human_size(size)}, {time.time() - started:.1f}s)')

    stale = snapshots_to_prune(os.listdir(args.out_dir), args.keep)
    for name in stale:
        os.remove(os.path.join(args.out_dir, name))
    if stale:
        print(f'Pruned {len(stale)} snapshot(s) beyond --keep {args.keep}')
    return 0


# --------------------------------------------------------------------------
# Restore
# --------------------------------------------------------------------------

def load_snapshot(path: str):
    opener = gzip.open if path.endswith('.gz') else open
    with opener(path, 'rt', encoding='utf-8') as fh:
        snapshot = json.load(fh)
    validate_snapshot(snapshot)
    return snapshot


def do_restore(args) -> int:
    snapshot = load_snapshot(args.restore)
    client = Firestore(args.key_file)

    if snapshot.get('project') != client.project and not args.force:
        print(f'Refusing to restore a snapshot of {snapshot.get("project")!r} '
              f'into {client.project!r}. Pass --force to override.',
              file=sys.stderr)
        return 2

    writes = restore_writes(snapshot, client.project, client.database)
    skipped = len(snapshot['documents']) - len(writes)

    print(f'Snapshot : {args.restore}')
    print(f'Taken    : {snapshot.get("createdAt")}')
    print(f'Target   : {client.project} {client.database}')
    print(f'Documents: {len(writes)} to write'
          + (f' ({skipped} placeholder(s) skipped)' if skipped else ''))
    for cid in snapshot.get('collections', []):
        print(f'  - {cid}')

    if not args.confirm:
        print('\nDRY RUN — nothing was written. '
              'Re-run with --confirm to restore.')
        return 0

    print('\nRestoring (upsert; documents absent from the snapshot are left '
          'untouched) ...')
    written = 0
    for batch in chunks(writes, COMMIT_BATCH_SIZE):
        client.commit(batch)
        written += len(batch)
        print(f'  {written}/{len(writes)}', flush=True)
    print(f'Restored {written} documents.')
    return 0


# --------------------------------------------------------------------------

def build_parser():
    p = argparse.ArgumentParser(
        description='Back up or restore the RoadMate Firestore database.')
    p.add_argument('--key-file', default=DEFAULT_KEY_FILE,
                   help='Admin service account JSON '
                        f'(default: {DEFAULT_KEY_FILE})')
    p.add_argument('--out-dir', default=DEFAULT_OUT_DIR,
                   help=f'snapshot directory (default: {DEFAULT_OUT_DIR})')
    p.add_argument('--keep', type=int, default=DEFAULT_KEEP,
                   help='snapshots to retain; 0 keeps all '
                        f'(default: {DEFAULT_KEEP})')
    p.add_argument('--incremental', action='store_true',
                   help='carry append-only reports forward from the newest '
                        'snapshot instead of re-reading them (far fewer reads; '
                        'self-repairs to a full backup on any count mismatch)')
    p.add_argument('--quiet', action='store_true',
                   help='only print the summary (for cron logs)')
    p.add_argument('--no-verify', action='store_true',
                   help='skip the count() cross-check after the walk')
    p.add_argument('--restore', metavar='SNAPSHOT',
                   help='restore from a snapshot instead of backing up '
                        '(dry run unless --confirm)')
    p.add_argument('--confirm', action='store_true',
                   help='actually write during --restore')
    p.add_argument('--force', action='store_true',
                   help='allow restoring a snapshot from another project')
    p.add_argument('--self-test', action='store_true',
                   help='run offline unit tests and exit')
    return p


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    if args.self_test:
        from backup_firestore_test import run  # noqa: PLC0415
        return run()
    if args.restore:
        return do_restore(args)
    if not os.path.exists(args.key_file):
        print(f'Service account key not found: {args.key_file}', file=sys.stderr)
        return 2
    return do_backup(args)


if __name__ == '__main__':
    sys.exit(main())
