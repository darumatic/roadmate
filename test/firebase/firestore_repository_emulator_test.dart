import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site.dart';
import 'package:roadmate/models/site_report.dart';
import 'package:roadmate/services/firestore_site_repository.dart';
import 'package:roadmate/services/rate_limit.dart';

// NOTE: `Firebase.initializeApp` needs a real platform plugin, which the
// plain `flutter test` VM does not have — run this suite from a host with
// native FlutterFire support (macOS/Android) against the emulators:
//   FIREBASE_EMULATOR_TESTS=true firebase emulators:exec --only firestore,auth \
//     "flutter test test/firebase/firestore_repository_emulator_test.dart"
// The rules themselves are covered headlessly in CI by test/rules/rules_test.mjs,
// whose batch helpers mirror FirestoreSiteRepository exactly.
const _projectId = 'roadmate-b1551';
final _runEmulatorTests =
    Platform.environment['FIREBASE_EMULATOR_TESTS'] == 'true';

void main() {
  group(
    'FirestoreSiteRepository emulator',
    skip: _runEmulatorTests
        ? false
        : 'Set FIREBASE_EMULATOR_TESTS=true and run through Firebase emulators.',
    () {
      late FirebaseApp app;
      late FirebaseAuth auth;
      late FirebaseFirestore firestore;
      late FirestoreSiteRepository repo;

      setUpAll(() async {
        app = await Firebase.initializeApp(
          name: 'firestore-repository-emulator',
          options: const FirebaseOptions(
            apiKey: 'fake-api-key',
            appId: '1:123:web:test',
            messagingSenderId: '123',
            projectId: _projectId,
          ),
        );
        auth = FirebaseAuth.instanceFor(app: app);
        firestore = FirebaseFirestore.instanceFor(app: app);
        firestore.useFirestoreEmulator('localhost', 8080);
        firestore.settings = const Settings(persistenceEnabled: false);
        await auth.useAuthEmulator('localhost', 9099);
        repo = FirestoreSiteRepository(firestore: firestore, auth: auth);
      });

      setUp(() async {
        await _clearFirestoreEmulator();
        await auth.signOut();
        await auth.signInAnonymously();
      });

      tearDownAll(() async {
        await app.delete();
      });

      test(
        'addSite writes a pending site hidden from approved site stream',
        () async {
          await repo.addSite(_site('site-1'));

          final doc = await firestore.collection('sites').doc('site-1').get();
          expect(doc.exists, isTrue);
          expect(doc.data()?['approved'], isFalse);
          expect(doc.data()?['createdBy'], auth.currentUser!.uid);

          final visible = await repo.watchSites().first;
          expect(visible, isEmpty);
        },
      );

      test(
        'vote creates a status report and updates the site counters',
        () async {
          await repo.addSite(_site('site-1'));

          await repo.vote('site-1', SiteStatus.blitz);

          final site = await firestore.collection('sites').doc('site-1').get();
          expect(site.data()?['currentStatus'], 'blitz');
          expect(site.data()?['blitzVotes'], 1);
          expect(site.data()?['lastReportAt'], isA<Timestamp>());

          final reports = await firestore
              .collection('sites')
              .doc('site-1')
              .collection('reports')
              .get();
          expect(reports.docs, hasLength(1));
          expect(reports.docs.single.data()['status'], 'blitz');
          expect(reports.docs.single.data()['uid'], auth.currentUser!.uid);
        },
      );

      test('report trims optional fields and touches lastReportAt', () async {
        await repo.addSite(_site('site-1'));

        await repo.report(
          'site-1',
          ActivityReportType.delays,
          activityNote: '  Queue back to the ramp  ',
          reporterName: '  Sam  ',
        );

        final report =
            (await firestore
                    .collection('sites')
                    .doc('site-1')
                    .collection('reports')
                    .get())
                .docs
                .single
                .data();
        expect(report['activityType'], 'delays');
        expect(report['activityNote'], 'Queue back to the ramp');
        expect(report['reporterName'], 'Sam');

        final site = await firestore.collection('sites').doc('site-1').get();
        expect(site.data()?['lastReportAt'], isA<Timestamp>());
      });

      test(
        'toggleFavourite only changes the signed-in user favourite doc',
        () async {
          await repo.toggleFavourite('site-1');

          final favourite = firestore
              .collection('users')
              .doc(auth.currentUser!.uid)
              .collection('favourites')
              .doc('site-1');
          expect((await favourite.get()).exists, isTrue);

          await repo.toggleFavourite('site-1');
          expect((await favourite.get()).exists, isFalse);
        },
      );

      test(
        'rules reject approved community sites and cross-user favourites',
        () async {
          await expectLater(
            firestore.collection('sites').doc('bad-site').set({
              ..._site('bad-site').toMap(),
              'approved': true,
              'createdBy': auth.currentUser!.uid,
              'createdAt': FieldValue.serverTimestamp(),
            }),
            throwsA(isA<FirebaseException>()),
          );

          await expectLater(
            firestore
                .collection('users')
                .doc('someone-else')
                .collection('favourites')
                .doc('site-1')
                .set({'favouritedAt': FieldValue.serverTimestamp()}),
            throwsA(isA<FirebaseException>()),
          );
        },
      );

      test(
        'first-ever action creates the rate-limit ledger via the retry path',
        () async {
          await repo.addSite(_site('site-1'));

          // No ledger doc exists yet, so the increment attempt fails on the
          // missing-doc precondition and the reset retry must create it.
          await repo.vote('site-1', SiteStatus.blitz);

          final ledger = await firestore
              .doc('users/${auth.currentUser!.uid}/limits/actions')
              .get();
          expect(ledger.data()?['count'], 1);
          expect(ledger.data()?['windowStart'], isA<Timestamp>());
          expect(ledger.data()?['lastActionAt'], isA<Timestamp>());
        },
      );

      test('5 actions succeed, the 6th is rate-limited and changes nothing '
          '(issue #15 redux)', () async {
        await repo.addSite(_site('site-1'));
        await repo.addSite(_site('site-2'));

        // 5 mixed actions across two sites — the window is global.
        await repo.vote('site-1', SiteStatus.blitz);
        await repo.vote('site-1', SiteStatus.open);
        await repo.report('site-1', ActivityReportType.delays);
        await repo.report('site-2', ActivityReportType.longQueue);
        await repo.vote('site-2', SiteStatus.closed);

        final uid = auth.currentUser!.uid;
        final ledger = await firestore.doc('users/$uid/limits/actions').get();
        expect(ledger.data()?['count'], 5);

        await expectLater(
          repo.vote('site-1', SiteStatus.open),
          throwsA(isA<RateLimitedException>()),
        );
        await expectLater(
          repo.report('site-1', ActivityReportType.policePresent),
          throwsA(isA<RateLimitedException>()),
        );

        // The denied batches were atomic: no counter moved, no report or
        // ledger increment landed.
        final site1 = await firestore.collection('sites').doc('site-1').get();
        expect(site1.data()?['blitzVotes'], 1);
        expect(site1.data()?['openVotes'], 1);
        final reports = await firestore
            .collection('sites')
            .doc('site-1')
            .collection('reports')
            .get();
        expect(reports.docs, hasLength(3));
        final after = await firestore.doc('users/$uid/limits/actions').get();
        expect(after.data()?['count'], 5);
      });
    },
  );
}

Site _site(String id) {
  return Site(
    id: id,
    name: 'Test Site',
    type: SiteType.checkingStation,
    state: AusState.nsw,
    suburb: 'Marulan',
    address: 'Hume Highway',
  );
}

Future<void> _clearFirestoreEmulator() async {
  final request = await HttpClient().deleteUrl(
    Uri.parse(
      'http://localhost:8080/emulator/v1/projects/$_projectId/databases/(default)/documents',
    ),
  );
  final response = await request.close();
  if (response.statusCode != 200) {
    throw StateError(
      'Could not clear Firestore emulator: HTTP ${response.statusCode}',
    );
  }
}
