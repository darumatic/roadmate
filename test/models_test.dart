import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site.dart';
import 'package:roadmate/models/site_report.dart';
import 'package:roadmate/services/site_repository.dart';

void main() {
  group('enums', () {
    test('SiteType round-trips through json value', () {
      for (final t in SiteType.values) {
        expect(SiteType.fromJsonValue(t.jsonValue), t);
      }
    });

    test('AusState resolves by code case-insensitively', () {
      expect(AusState.fromCode('vic'), AusState.vic);
      expect(AusState.fromCode('NSW'), AusState.nsw);
    });

    test('SiteStatus.fromName falls back to open', () {
      expect(SiteStatus.fromName('blitz'), SiteStatus.blitz);
      expect(SiteStatus.fromName(null), SiteStatus.open);
      expect(SiteStatus.fromName('garbage'), SiteStatus.open);
    });

    test('activity labels and wire values renamed per issue #4', () {
      expect(ActivityReportType.defectChecks.label, 'BGD');
      expect(ActivityReportType.noActivity.label, 'Camera Only');
      // Wire values must match the firestore.rules activityType allow-list.
      expect(ActivityReportType.defectChecks.wire, 'BGD');
      expect(ActivityReportType.noActivity.wire, 'Camera Only');
      expect(ActivityReportType.longQueue.wire, 'longQueue');
      // New wire values, legacy enum names and the rules-era typo all parse.
      expect(
        ActivityReportType.fromName('BGD'),
        ActivityReportType.defectChecks,
      );
      expect(
        ActivityReportType.fromName('Camera Only'),
        ActivityReportType.noActivity,
      );
      expect(
        ActivityReportType.fromName('defectChecks'),
        ActivityReportType.defectChecks,
      );
      expect(
        ActivityReportType.fromName('noActivity'),
        ActivityReportType.noActivity,
      );
      expect(
        ActivityReportType.fromName('CameraOnly'),
        ActivityReportType.noActivity,
      );
    });
  });

  group('Site serialization', () {
    test('fromMap / toMap round-trip preserves core fields', () {
      const site = Site(
        id: 'nsw-0',
        name: 'Eastern Creek Weighbridge',
        type: SiteType.weighbridge,
        state: AusState.nsw,
        suburb: 'Eastern Creek',
        address: 'Great Western Hwy',
        lat: -33.8,
        lng: 150.86,
        blitzVotes: 2,
      );
      final restored = Site.fromMap(site.id, site.toMap());
      expect(restored.name, site.name);
      expect(restored.type, site.type);
      expect(restored.state, site.state);
      expect(restored.lat, site.lat);
      expect(restored.blitzVotes, 2);
    });

    test('fromSeedJson maps type and direction', () {
      final site = Site.fromSeedJson(
        {
          'name': 'Marulan North',
          'type': 'checking_station',
          'suburb': 'Marulan',
          'address': 'Hume Hwy',
          'lat': -34.7,
          'lng': 150.0,
          'direction': 'northbound',
        },
        state: AusState.nsw,
        id: 'nsw-1',
      );
      expect(site.type, SiteType.checkingStation);
      expect(site.direction, 'northbound');
      expect(site.state, AusState.nsw);
    });
  });

  group('SiteReport serialization', () {
    test('round-trips status and timestamp', () {
      final report = SiteReport(
        id: 'r1',
        siteId: 's1',
        createdAt: DateTime(2026, 6, 29, 10, 30),
        status: SiteStatus.blitz,
      );
      final restored = SiteReport.fromMap(report.id, report.toMap());
      expect(restored.status, SiteStatus.blitz);
      expect(restored.createdAt, report.createdAt);
      expect(restored.siteId, 's1');
    });

    test('round-trips categorized activity reports', () {
      final report = SiteReport(
        id: 'r2',
        siteId: 's1',
        createdAt: DateTime(2026, 6, 29, 11),
        activityType: ActivityReportType.longQueue,
        activityNote: 'Queue back to the ramp',
        reporterName: 'Sam',
      );
      final restored = SiteReport.fromMap(report.id, report.toMap());
      expect(restored.activityType, ActivityReportType.longQueue);
      expect(restored.activityNote, 'Queue back to the ramp');
      expect(restored.reporterName, 'Sam');
      expect(restored.isActivityReport, isTrue);
    });

    test('round-trips reporterLevel and tolerates its absence', () {
      final report = SiteReport(
        id: 'r3',
        siteId: 's1',
        createdAt: DateTime(2026, 8, 4, 9),
        activityType: ActivityReportType.delays,
        reporterName: 'Sam',
        reporterLevel: 3,
      );
      final restored = SiteReport.fromMap(report.id, report.toMap());
      expect(restored.reporterLevel, 3);

      // Docs written by older clients have no reporterLevel at all; web can
      // also decode Firestore ints as doubles.
      final legacy = SiteReport.fromMap('r4', {
        'siteId': 's1',
        'createdAt': '2026-08-04T09:00:00',
        'activityType': 'delays',
      });
      expect(legacy.reporterLevel, isNull);
      final fromDouble = SiteReport.fromMap('r5', {
        'siteId': 's1',
        'createdAt': '2026-08-04T09:00:00',
        'activityType': 'delays',
        'reporterLevel': 2.0,
      });
      expect(fromDouble.reporterLevel, 2);
    });
  });

  // Issue #48. Shipped phones can't be hot-updated and read an unknown status
  // string as OPEN, so Camera Only / BGD must never reach the wire as a
  // status: these pin the three places it could leak, and the exact document
  // a press is stored as instead.
  group('display-only statuses never reach the wire (issue #48)', () {
    test('only the row of three is stored', () {
      expect(SiteStatus.votable, [
        SiteStatus.open,
        SiteStatus.blitz,
        SiteStatus.closed,
      ]);
      expect(SiteStatus.values.where((s) => s.isStored), SiteStatus.votable);
      expect(SiteStatus.cameraOnly.isStored, isFalse);
      expect(SiteStatus.unknown.isStored, isFalse);
    });

    test('Camera Only / BGD is labelled and coloured as the blue status', () {
      expect(SiteStatus.cameraOnly.label, 'Camera Only / BGD');
      expect(SiteStatus.cameraOnly.color.toARGB32(), 0xFF3B82F6);
    });

    test('a display-only name in a document parses as open, exactly as it '
        'does on every shipped build', () {
      expect(SiteStatus.fromName('cameraOnly'), SiteStatus.open);
      expect(SiteStatus.fromName('unknown'), SiteStatus.open);
      for (final stored in SiteStatus.votable) {
        expect(SiteStatus.fromName(stored.name), stored);
      }
    });

    test('Site.toMap never emits a display-only status', () {
      const site = Site(
        id: 's1',
        name: 'Marulan',
        type: SiteType.checkingStation,
        state: AusState.nsw,
        suburb: 'Marulan',
        address: 'Hume Hwy',
      );
      for (final status in SiteStatus.values) {
        final written = site.copyWith(currentStatus: status).toMap();
        expect(
          written['currentStatus'],
          status.isStored ? status.name : 'open',
          reason: '$status',
        );
      }
    });

    test('BGD and Camera Only left the Report dialog but still parse', () {
      expect(ActivityReportType.reportable, [
        ActivityReportType.longQueue,
        ActivityReportType.delays,
        ActivityReportType.policePresent,
        ActivityReportType.other,
      ]);
      expect(ActivityReportType.values.where((t) => t.meansCameraOnly), [
        ActivityReportType.defectChecks,
        ActivityReportType.noActivity,
      ]);
      expect(
        ActivityReportType.fromName('Camera Only'),
        ActivityReportType.noActivity,
      );
      expect(
        ActivityReportType.fromName('BGD'),
        ActivityReportType.defectChecks,
      );
    });

    test('a Camera Only / BGD press is byte-for-byte the legacy Camera Only '
        'activity report', () {
      const serverTime = 'SERVER_TIME';
      final payload = activityReportPayload(
        siteId: 'nsw-1',
        uid: 'u1',
        type: ActivityReportType.noActivity,
        reporterName: '  Dusty Nomad ',
        reporterLevel: 2,
        serverTime: serverTime,
      );
      expect(payload, {
        'siteId': 'nsw-1',
        'activityType': 'Camera Only',
        'uid': 'u1',
        'createdAt': serverTime,
        'reporterName': 'Dusty Nomad',
        'reporterLevel': 2,
      });
      // The rules make a report EITHER a vote OR an activity report: a
      // `status` key here would be refused, and read as OPEN if it weren't.
      expect(payload.containsKey('status'), isFalse);
    });

    test('an activity payload stays inside the key set the rules accept, and '
        'leaves absent values out rather than writing nulls', () {
      const allowed = {
        'siteId', 'activityType', 'activityNote', 'reporterName', //
        'reporterLevel', 'uid', 'createdAt',
      };
      final full = activityReportPayload(
        siteId: 's',
        uid: 'u',
        type: ActivityReportType.other,
        note: ' queue past the ramp ',
        reporterName: 'Dusty',
        reporterLevel: 1,
        serverTime: 0,
      );
      expect(full.keys.toSet(), allowed);
      expect(full['activityNote'], 'queue past the ramp');

      final bare = activityReportPayload(
        siteId: 's',
        uid: 'u',
        type: ActivityReportType.other,
        note: '   ',
        reporterName: '',
        reporterLevel: 1,
        serverTime: 0,
      );
      expect(bare.keys, isNot(contains('activityNote')));
      expect(bare.keys, isNot(contains('reporterName')));
      expect(bare.values, everyElement(isNotNull));
    });
  });

  group('parseNhvrNationalData', () {
    final sample = {
      'states': {
        'NSW': {
          'facility_type': 'Heavy Vehicle Safety Station (HVSS)',
          'stations': [
            {
              'site_id': 'HVSS-NSW-001',
              'location': 'Marulan (Northbound)',
              'route': 'Hume Highway',
              'direction': 'Northbound',
              'gvm_requirement_tonnes': 8.0,
            },
          ],
        },
        'VIC': {
          'facility_type': 'Roadside Weighbridge & Intercept Sites',
          'stations': [
            {
              'site_id': 'WB-VIC-001',
              'location': 'Broadford Weighbridge',
              'route': 'Hume Freeway',
              'direction': 'Both',
              'notes': 'NHVR/VicRoads Intercept',
            },
          ],
        },
        'WA': {'facility_type': 'None (Non-NHVR)', 'stations': []},
      },
    };

    test('flattens stations and skips empty states', () {
      final sites = parseNhvrNationalData(sample);
      expect(sites.length, 2);
      expect(sites.where((s) => s.state == AusState.wa), isEmpty);
    });

    test('maps facility type to SiteType and uses site_id as id', () {
      final sites = parseNhvrNationalData(sample);
      final nsw = sites.firstWhere((s) => s.state == AusState.nsw);
      expect(nsw.id, 'HVSS-NSW-001');
      expect(nsw.type, SiteType.checkingStation);
      final vic = sites.firstWhere((s) => s.state == AusState.vic);
      expect(vic.type, SiteType.weighbridge);
    });

    test('normalises direction (Both -> none) and derives suburb/note', () {
      final sites = parseNhvrNationalData(sample);
      final nsw = sites.firstWhere((s) => s.state == AusState.nsw);
      expect(nsw.direction, 'northbound');
      expect(nsw.suburb, 'Marulan');
      expect(nsw.note, contains('8'));
      final vic = sites.firstWhere((s) => s.state == AusState.vic);
      expect(vic.direction, isNull); // "Both"
      expect(vic.note, 'NHVR/VicRoads Intercept');
    });

    test('accepts all four compass directions', () {
      Site siteWithDirection(String? raw) => Site.fromNhvrStation(
        {'site_id': 'X-1', 'location': 'Somewhere', 'direction': raw},
        state: AusState.nsw,
        facilityType: 'HVSS',
      );

      expect(siteWithDirection('Northbound').direction, 'northbound');
      expect(siteWithDirection('Southbound').direction, 'southbound');
      expect(siteWithDirection('Eastbound').direction, 'eastbound');
      expect(siteWithDirection('Westbound').direction, 'westbound');
      expect(siteWithDirection('Both').direction, isNull);
    });
  });
}
