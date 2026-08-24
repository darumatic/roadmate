#!/usr/bin/env python3
"""Offline unit tests for scripts/backup_firestore.py.

Run directly (``python3 scripts/backup_firestore_test.py``), via
``scripts/backup_firestore.py --self-test``, or as part of ``flutter test``
through ``test/backup_firestore_test.dart``. No network, no credentials.
"""

import datetime as dt
import gzip
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import backup_firestore as bf  # noqa: E402


class PureHelpersTest(unittest.TestCase):
    def test_snapshot_filename_sorts_chronologically(self):
        earlier = bf.snapshot_filename(dt.datetime(2026, 7, 26, 3, 0, 0))
        later = bf.snapshot_filename(dt.datetime(2026, 7, 26, 3, 0, 1))
        next_year = bf.snapshot_filename(dt.datetime(2027, 1, 1, 0, 0, 0))
        self.assertLess(earlier, later)
        self.assertLess(later, next_year)
        self.assertTrue(bf.is_snapshot_name(earlier))

    def test_relative_path_strips_the_database_prefix(self):
        self.assertEqual(
            bf.relative_path('projects/roadmate-b1551/databases/(default)'
                             '/documents/sites/abc/reports/r1'),
            'sites/abc/reports/r1')
        with self.assertRaises(ValueError):
            bf.relative_path('sites/abc')

    def test_document_name_round_trips(self):
        name = bf.document_name('roadmate-b1551', '(default)', 'users/u1')
        self.assertEqual(bf.relative_path(name), 'users/u1')

    def test_collection_ids_covers_subcollections(self):
        self.assertEqual(
            bf.collection_ids(['sites/a', 'sites/a/reports/r1',
                               'users/u1/favourites/s1', 'config/app']),
            ['config', 'favourites', 'reports', 'sites', 'users'])


class RetentionTest(unittest.TestCase):
    def names(self, *days):
        return [bf.snapshot_filename(dt.datetime(2026, 7, d)) for d in days]

    def test_keeps_the_newest_n_and_prunes_the_rest(self):
        names = self.names(1, 2, 3, 4, 5)
        self.assertEqual(bf.snapshots_to_prune(names, 2), self.names(1, 2, 3))

    def test_keep_zero_disables_pruning(self):
        names = self.names(1, 2, 3)
        self.assertEqual(bf.snapshots_to_prune(names, 0), [])
        self.assertEqual(bf.snapshots_to_prune(names, -1), [])

    def test_nothing_to_prune_when_under_the_limit(self):
        self.assertEqual(bf.snapshots_to_prune(self.names(1, 2), 30), [])

    def test_never_prunes_unrelated_files(self):
        names = self.names(1, 2, 3) + ['notes.txt', 'other-backup.json.gz',
                                       'roadmate-firestore-x.json.gz.partial']
        pruned = bf.snapshots_to_prune(names, 1)
        self.assertEqual(pruned, self.names(1, 2))


class CountCrossCheckTest(unittest.TestCase):
    def test_counts_documents_by_collection_id(self):
        self.assertEqual(
            bf.count_by_collection_id([
                {'path': 'sites/a'}, {'path': 'sites/b'},
                {'path': 'sites/a/reports/r1'}, {'path': 'sites/b/reports/r2'},
                {'path': 'users/u1/favourites/s1'}]),
            {'sites': 2, 'reports': 2, 'favourites': 1})

    def test_excludes_placeholder_parents(self):
        # count() ignores documents that exist only as subcollection parents;
        # counting them here made every run warn about a phantom drop.
        self.assertEqual(
            bf.count_by_collection_id([
                {'path': 'users/real'},
                {'path': 'users/ghost', 'missing': True},
                {'path': 'users/ghost/favourites/s1'}]),
            {'users': 1, 'favourites': 1})

    def test_no_mismatch_when_the_walk_agrees(self):
        self.assertEqual(
            bf.compare_counts({'sites': 41, 'reports': 834},
                              {'sites': 41, 'reports': 834}), {})

    def test_reports_a_dropped_document(self):
        # The failure this guards against: the walk silently returns fewer
        # documents than the database holds.
        self.assertEqual(
            bf.compare_counts({'sites': 37, 'reports': 834},
                              {'sites': 41, 'reports': 834}),
            {'sites': (37, 41)})

    def test_reports_a_collection_the_walk_missed_entirely(self):
        self.assertEqual(
            bf.compare_counts({'sites': 41}, {'sites': 41, 'reports': 834}),
            {'reports': (0, 834)})


class ValidationTest(unittest.TestCase):
    def snapshot(self, **overrides):
        base = {'formatVersion': bf.FORMAT_VERSION,
                'documents': [{'path': 'sites/a', 'fields': {}}]}
        base.update(overrides)
        return base

    def test_accepts_a_well_formed_snapshot(self):
        bf.validate_snapshot(self.snapshot())

    def test_rejects_a_future_format_version(self):
        with self.assertRaises(ValueError):
            bf.validate_snapshot(self.snapshot(formatVersion=99))

    def test_rejects_a_non_object(self):
        with self.assertRaises(ValueError):
            bf.validate_snapshot([1, 2, 3])

    def test_rejects_missing_documents_list(self):
        snap = self.snapshot()
        del snap['documents']
        with self.assertRaises(ValueError):
            bf.validate_snapshot(snap)

    def test_rejects_a_collection_path_masquerading_as_a_document(self):
        # An odd number of segments is a collection, not a document; writing it
        # back would fail mid-restore.
        with self.assertRaises(ValueError):
            bf.validate_snapshot(self.snapshot(documents=[{'path': 'sites'}]))


class RestoreWritesTest(unittest.TestCase):
    def test_builds_full_document_overwrites(self):
        snapshot = {'documents': [
            {'path': 'sites/a', 'fields': {'name': {'stringValue': 'Marulan'}}},
        ]}
        writes = bf.restore_writes(snapshot, 'roadmate-b1551', '(default)')
        self.assertEqual(writes, [{'update': {
            'name': 'projects/roadmate-b1551/databases/(default)/documents'
                    '/sites/a',
            'fields': {'name': {'stringValue': 'Marulan'}},
        }}])
        # No updateMask: the document is replaced wholesale, so fields deleted
        # since the snapshot do not survive the restore.
        self.assertNotIn('updateMask', writes[0])

    def test_skips_placeholder_parents(self):
        snapshot = {'documents': [
            {'path': 'users/ghost', 'missing': True},
            {'path': 'users/ghost/favourites/s1', 'fields': {}},
        ]}
        writes = bf.restore_writes(snapshot, 'p', '(default)')
        self.assertEqual(len(writes), 1)
        self.assertTrue(writes[0]['update']['name'].endswith(
            'users/ghost/favourites/s1'))

    def test_chunks_respect_the_commit_limit(self):
        self.assertLessEqual(bf.COMMIT_BATCH_SIZE, 500)
        batches = list(bf.chunks(list(range(1000)), bf.COMMIT_BATCH_SIZE))
        self.assertEqual(sum(len(b) for b in batches), 1000)
        self.assertTrue(all(len(b) <= bf.COMMIT_BATCH_SIZE for b in batches))


class FakeFirestore:
    """In-memory stand-in for the REST client, keyed by relative path."""

    project = 'roadmate-b1551'
    database = '(default)'

    def __init__(self, docs):
        self.docs = docs  # {relative path: fields dict or None if missing}
        self.committed = []

    def _children(self, parent):
        depth = len(parent.split('/')) if parent else 0
        out = set()
        for path in self.docs:
            if parent and not path.startswith(parent + '/'):
                continue
            segments = path.split('/')
            if len(segments) > depth + 1:
                out.add(segments[depth])
        return sorted(out)

    def list_collection_ids(self, parent_path=''):
        return self._children(parent_path)

    def list_documents(self, parent_path, collection_id):
        prefix = (f'{parent_path}/{collection_id}/' if parent_path
                  else f'{collection_id}/')
        out = []
        for path, fields in sorted(self.docs.items()):
            if not path.startswith(prefix):
                continue
            if len(path.split('/')) != len(prefix.split('/')):
                continue
            doc = {'name': bf.document_name(self.project, self.database, path)}
            if fields is not None:
                doc['fields'] = fields
                doc['createTime'] = '2026-07-01T00:00:00Z'
                doc['updateTime'] = '2026-07-20T00:00:00Z'
            out.append(doc)
        return out

    def commit(self, writes):
        self.committed.extend(writes)
        for write in writes:
            update = write['update']
            self.docs[bf.relative_path(update['name'])] = update['fields']
        return {}


class ToRecordTest(unittest.TestCase):
    def test_keeps_fields_verbatim(self):
        record = bf.to_record({
            'name': 'projects/p/databases/(default)/documents/sites/a',
            'fields': {'lastReportAt': {'timestampValue': '2026-07-20T01:02:03Z'},
                       'openVotes': {'integerValue': '12'},
                       'location': {'geoPointValue': {'latitude': -34.7,
                                                      'longitude': 150.0}}},
            'createTime': '2026-07-01T00:00:00Z',
            'updateTime': '2026-07-20T00:00:00Z',
        })
        self.assertEqual(record['path'], 'sites/a')
        self.assertEqual(record['fields']['openVotes'], {'integerValue': '12'})
        self.assertEqual(record['fields']['location']['geoPointValue'],
                         {'latitude': -34.7, 'longitude': 150.0})
        self.assertNotIn('missing', record)

    def test_flags_a_document_with_no_data_as_missing(self):
        record = bf.to_record(
            {'name': 'projects/p/databases/(default)/documents/users/ghost'})
        self.assertTrue(record['missing'])
        self.assertNotIn('fields', record)

    def test_keeps_an_empty_but_real_document(self):
        # A document that exists with zero fields still has a createTime; it
        # must not be confused with a parent-only placeholder.
        record = bf.to_record({
            'name': 'projects/p/databases/(default)/documents/users/u/favourites/s',
            'createTime': '2026-07-01T00:00:00Z',
            'updateTime': '2026-07-01T00:00:00Z',
        })
        self.assertNotIn('missing', record)
        self.assertEqual(record['fields'], {})


class WalkTest(unittest.TestCase):
    def client(self):
        return FakeFirestore({
            'sites/a': {'name': {'stringValue': 'Marulan'}},
            'sites/a/reports/r1': {'status': {'stringValue': 'open'}},
            'sites/a/reports/r2': {'status': {'stringValue': 'blitz'}},
            'sites/b': {'name': {'stringValue': 'Gundagai'}},
            'users/u1': {'email': {'stringValue': 'a@b.c'}},
            'users/u1/favourites/a': {},
            'users/ghost': None,  # parent-only placeholder
            'users/ghost/limits/actions': {'count': {'integerValue': '3'}},
            'config/app': {'minVersion': {'stringValue': '0.1.40'}},
        })

    def test_walks_every_document_including_nested_subcollections(self):
        docs = bf.walk(self.client(), verbose=False)
        self.assertEqual(
            sorted(d['path'] for d in docs),
            ['config/app', 'sites/a', 'sites/a/reports/r1',
             'sites/a/reports/r2', 'sites/b', 'users/ghost',
             'users/ghost/limits/actions', 'users/u1', 'users/u1/favourites/a'])

    def test_preserves_raw_field_payloads_and_flags_placeholders(self):
        docs = {d['path']: d for d in bf.walk(self.client(), verbose=False)}
        self.assertEqual(docs['sites/a']['fields'],
                         {'name': {'stringValue': 'Marulan'}})
        self.assertEqual(docs['sites/a']['updateTime'], '2026-07-20T00:00:00Z')
        self.assertTrue(docs['users/ghost'].get('missing'))
        self.assertNotIn('fields', docs['users/ghost'])

    def test_round_trips_through_a_snapshot_file(self):
        client = self.client()
        documents = bf.walk(client, verbose=False)
        snapshot = {'formatVersion': bf.FORMAT_VERSION,
                    'project': client.project, 'database': client.database,
                    'documentCount': len(documents),
                    'collections': bf.collection_ids(
                        d['path'] for d in documents),
                    'documents': documents}
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, bf.snapshot_filename(dt.datetime.now()))
            with gzip.open(path, 'wt', encoding='utf-8') as fh:
                json.dump(snapshot, fh)
            reloaded = bf.load_snapshot(path)

        self.assertEqual(reloaded['documents'], documents)
        self.assertEqual(reloaded['collections'],
                         ['config', 'favourites', 'limits', 'reports',
                          'sites', 'users'])

        writes = bf.restore_writes(reloaded, client.project, client.database)
        # Every real document is restored; the placeholder parent is not.
        self.assertEqual(len(writes), len(documents) - 1)
        restored = {bf.relative_path(w['update']['name']): w['update']['fields']
                    for w in writes}
        self.assertEqual(restored['sites/a/reports/r1'],
                         {'status': {'stringValue': 'open'}})
        self.assertEqual(restored['users/ghost/limits/actions'],
                         {'count': {'integerValue': '3'}})


def report(path, created_at, **fields):
    doc = {'path': path, 'fields': dict(fields)}
    doc['fields']['createdAt'] = {'timestampValue': created_at}
    return doc


class IncrementalTest(unittest.TestCase):
    def test_newest_snapshot_picks_the_latest(self):
        names = [bf.snapshot_filename(dt.datetime(2026, 7, d)) for d in (3, 1, 2)]
        self.assertEqual(bf.newest_snapshot(names + ['README']),
                         bf.snapshot_filename(dt.datetime(2026, 7, 3)))

    def test_newest_snapshot_is_none_on_an_empty_directory(self):
        self.assertIsNone(bf.newest_snapshot([]))
        self.assertIsNone(bf.newest_snapshot(['notes.txt']))

    def test_watermark_is_the_latest_report_timestamp(self):
        docs = [
            report('sites/a/reports/r1', '2026-07-20T01:00:00Z'),
            report('sites/b/reports/r2', '2026-07-25T09:30:00Z'),
            report('sites/a/reports/r3', '2026-07-24T00:00:00Z'),
            {'path': 'sites/a', 'fields': {}},  # not a report
        ]
        self.assertEqual(bf.report_watermark(docs), '2026-07-25T09:30:00Z')

    def test_watermark_ignores_non_report_collections(self):
        # A newer favourite must not advance the reports watermark.
        docs = [report('sites/a/reports/r1', '2026-07-20T01:00:00Z'),
                {'path': 'users/u/favourites/s',
                 'fields': {'createdAt': {'timestampValue': '2026-07-26T00:00:00Z'}}}]
        self.assertEqual(bf.report_watermark(docs), '2026-07-20T01:00:00Z')

    def test_watermark_is_none_without_reports(self):
        # Forces a full backup rather than carrying nothing forward.
        self.assertIsNone(bf.report_watermark([{'path': 'sites/a', 'fields': {}}]))
        self.assertIsNone(bf.report_watermark(
            [{'path': 'sites/a/reports/r1', 'missing': True}]))

    def test_carried_reports_selects_only_reports(self):
        docs = [report('sites/a/reports/r1', '2026-07-20T01:00:00Z'),
                {'path': 'sites/a', 'fields': {}},
                {'path': 'users/u/favourites/s', 'fields': {}}]
        self.assertEqual([d['path'] for d in bf.carried_reports(docs)],
                         ['sites/a/reports/r1'])

    def test_merge_dedupes_on_the_watermark_boundary(self):
        # query_since uses >=, so the boundary report comes back again; the
        # merge must not duplicate it.
        old = report('sites/a/reports/r1', '2026-07-25T09:30:00Z')
        again = report('sites/a/reports/r1', '2026-07-25T09:30:00Z')
        new = report('sites/a/reports/r2', '2026-07-26T10:00:00Z')
        merged = bf.merge_documents([old], [again, new])
        self.assertEqual([d['path'] for d in merged],
                         ['sites/a/reports/r1', 'sites/a/reports/r2'])

    def test_merge_prefers_freshly_fetched_documents(self):
        stale = {'path': 'sites/a', 'fields': {'name': {'stringValue': 'old'}}}
        fresh = {'path': 'sites/a', 'fields': {'name': {'stringValue': 'new'}}}
        merged = bf.merge_documents([stale], [fresh])
        self.assertEqual(merged[0]['fields']['name']['stringValue'], 'new')

    def test_walk_can_skip_a_collection(self):
        client = FakeFirestore({
            'sites/a': {'name': {'stringValue': 'Marulan'}},
            'sites/a/reports/r1': {'status': {'stringValue': 'open'}},
            'users/u1': {},
            'users/u1/favourites/a': {},
        })
        paths = sorted(d['path'] for d in bf.walk(
            client, verbose=False, skip=frozenset(['reports'])))
        self.assertEqual(paths, ['sites/a', 'users/u1', 'users/u1/favourites/a'])

    def test_skipping_reports_leaves_the_rest_intact(self):
        client = FakeFirestore({f'sites/a/reports/r{i}': {} for i in range(50)}
                               | {'sites/a': {}})
        full = bf.walk(client, verbose=False)
        partial = bf.walk(client, verbose=False, skip=frozenset(['reports']))
        self.assertEqual(len(full), 51)
        self.assertEqual([d['path'] for d in partial], ['sites/a'])


class DisasterRecoveryTest(unittest.TestCase):
    """The scenario the whole script exists for: the database is gone."""

    def live_data(self):
        return {
            'sites/a': {'name': {'stringValue': 'Marulan'},
                        'openVotes': {'integerValue': '12'},
                        'location': {'geoPointValue': {'latitude': -34.71,
                                                       'longitude': 150.0}},
                        'approved': {'booleanValue': True}},
            'sites/a/reports/r1': {'status': {'stringValue': 'blitz'},
                                   'createdAt': {'timestampValue':
                                                 '2026-07-20T01:00:00Z'}},
            'sites/b': {'name': {'stringValue': 'Gundagai'}},
            'users/u1': {'email': {'stringValue': 'a@b.c'}},
            'users/u1/favourites/a': {},
            'userRoles/u1': {'role': {'stringValue': 'admin'}},
            'config/app': {'minVersion': {'stringValue': '0.1.46'}},
        }

    def test_a_wiped_database_is_rebuilt_exactly_from_a_snapshot(self):
        live = FakeFirestore(self.live_data())
        documents = bf.walk(live, verbose=False)

        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, bf.snapshot_filename(dt.datetime.now()))
            with gzip.open(path, 'wt', encoding='utf-8') as fh:
                json.dump({'formatVersion': bf.FORMAT_VERSION,
                           'project': live.project, 'database': live.database,
                           'documents': documents}, fh)

            # Catastrophe: everything is gone.
            wiped = FakeFirestore({})
            snapshot = bf.load_snapshot(path)
            writes = bf.restore_writes(snapshot, wiped.project, wiped.database)
            for batch in bf.chunks(writes, bf.COMMIT_BATCH_SIZE):
                wiped.commit(batch)

        self.assertEqual(wiped.docs, self.live_data())
        # And the rebuilt database backs up to the same snapshot.
        self.assertEqual(
            [d['path'] for d in bf.walk(wiped, verbose=False)],
            [d['path'] for d in documents])

    def test_restore_does_not_delete_documents_absent_from_the_snapshot(self):
        # Restoring an old snapshot must not wipe newer data.
        target = FakeFirestore({'sites/new': {'name': {'stringValue': 'Later'}}})
        snapshot = {'documents': [{'path': 'sites/a', 'fields': {}}]}
        for batch in bf.chunks(
                bf.restore_writes(snapshot, target.project, target.database),
                bf.COMMIT_BATCH_SIZE):
            target.commit(batch)
        self.assertIn('sites/new', target.docs)
        self.assertIn('sites/a', target.docs)

    def test_restore_batches_a_large_database(self):
        live = FakeFirestore({f'sites/s{i}': {'n': {'integerValue': str(i)}}
                              for i in range(950)})
        documents = bf.walk(live, verbose=False)
        wiped = FakeFirestore({})
        writes = bf.restore_writes({'documents': documents},
                                   wiped.project, wiped.database)
        batches = list(bf.chunks(writes, bf.COMMIT_BATCH_SIZE))
        for batch in batches:
            wiped.commit(batch)
        self.assertEqual(len(batches), 3)
        self.assertEqual(len(wiped.docs), 950)
        self.assertEqual(wiped.docs, live.docs)


class CliTest(unittest.TestCase):
    def test_restore_defaults_to_dry_run(self):
        args = bf.build_parser().parse_args(['--restore', 'snap.json.gz'])
        self.assertFalse(args.confirm)
        self.assertFalse(args.force)

    def test_default_retention_and_output_dir(self):
        args = bf.build_parser().parse_args([])
        self.assertEqual(args.keep, 30)
        self.assertTrue(args.out_dir.endswith('/backups'))
        self.assertIsNone(args.restore)

    def test_verification_is_on_by_default(self):
        # The count() cross-check is what makes --incremental safe; it must
        # never be off unless asked for explicitly.
        args = bf.build_parser().parse_args(['--incremental'])
        self.assertFalse(args.no_verify)
        self.assertTrue(args.incremental)


class UrlEncodingTest(unittest.TestCase):
    """Document IDs are user-chosen (a ``usernames`` key like ``big trucker``)
    and raw interpolation into the REST URL raises InvalidURL on a space —
    which silently killed every nightly backup from 2026-08-05. Paths must be
    percent-encoded, with the ``/`` separators preserved."""

    def _client(self, seen):
        fs = bf.Firestore.__new__(bf.Firestore)
        fs.root = 'https://firestore.example/v1/p/d/documents'
        fs._call = lambda url, payload=None: seen.append(url) or {}
        return fs

    def test_url_path_encodes_spaces_and_keeps_slashes(self):
        self.assertEqual(bf.url_path('usernames/big trucker'),
                         'usernames/big%20trucker')

    def test_url_path_plain_path_unchanged(self):
        self.assertEqual(bf.url_path('sites/abc123'), 'sites/abc123')

    def test_list_collection_ids_encodes_parent(self):
        seen = []
        self._client(seen).list_collection_ids('usernames/big trucker')
        self.assertIn('usernames/big%20trucker:listCollectionIds', seen[0])
        self.assertNotIn(' ', seen[0])

    def test_list_documents_encodes_parent(self):
        seen = []
        self._client(seen).list_documents('sites/spaced id', 'reports')
        self.assertIn('sites/spaced%20id/reports', seen[0])
        self.assertNotIn(' ', seen[0])


def run() -> int:
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromModule(sys.modules[__name__])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    sys.exit(run())
