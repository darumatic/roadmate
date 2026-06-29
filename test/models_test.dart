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
  });
}
