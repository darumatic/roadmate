import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site.dart';
import 'package:roadmate/models/site_report.dart';
import 'package:roadmate/services/firestore_site_repository.dart';

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
