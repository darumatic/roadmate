import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site_report.dart';
import 'package:roadmate/services/admin_repository.dart';

void main() {
  // Admin site edits: the full describing shape, never the derived or
  // moderation fields.
  group('siteEditData', () {
    Map<String, Object?> edit({String? note, String? direction}) =>
        siteEditData(
          name: '  Marulan HVSS  ',
          type: SiteType.checkingStation,
          state: AusState.vic,
          suburb: '  Marulan  ',
          address: '  Hume Hwy  ',
          direction: direction,
          note: note,
          lat: -34.71,
          lng: 149.99,
        );

    test('writes wire values and trims text fields', () {
      final data = edit(
        note: '  queue past the ramp  ',
        direction: 'southbound',
      );
      expect(data['name'], 'Marulan HVSS');
      expect(data['suburb'], 'Marulan');
      expect(data['address'], 'Hume Hwy');
      expect(data['type'], 'checking_station');
      expect(data['state'], 'VIC');
      expect(data['direction'], 'southbound');
      expect(data['note'], 'queue past the ramp');
      expect(data['lat'], -34.71);
      expect(data['lng'], 149.99);
    });

    test('a blank or missing note maps to null (field cleared)', () {
      expect(edit(note: '   ')['note'], isNull);
      expect(edit(note: null)['note'], isNull);
    });

    test('never touches derived or moderation fields', () {
      expect(
        edit().keys,
        unorderedEquals([
          'name',
          'type',
          'state',
          'suburb',
          'address',
          'direction',
          'note',
          'lat',
          'lng',
        ]),
      );
    });
  });

  // Admin activity-report edits (rules allow exactly these fields to change).
  group('activityReportEditData', () {
    test('writes the wire value for the chosen type', () {
      final data = activityReportEditData(
        ActivityReportType.defectChecks,
        'Trucks queued past the ramp',
      );
      expect(data['activityType'], 'BGD');
      expect(data['activityNote'], 'Trucks queued past the ramp');
    });

    test('trims the note', () {
      final data = activityReportEditData(
        ActivityReportType.longQueue,
        '  slow moving  ',
      );
      expect(data['activityNote'], 'slow moving');
    });

    test('a blank or missing note maps to null (field cleared)', () {
      expect(
        activityReportEditData(
          ActivityReportType.delays,
          '   ',
        )['activityNote'],
        isNull,
      );
      expect(
        activityReportEditData(ActivityReportType.delays, null)['activityNote'],
        isNull,
      );
    });
  });

  // The admin feed resolves site names from one cached sites fetch instead of
  // a get() per report; this predicate decides when that cache is refreshed.
  group('siteNamesCover', () {
    const names = {'s1': 'Marulan', 's2': 'Mt White'};

    test('covered when every referenced site is known', () {
      expect(siteNamesCover(names, ['s1', 's2', 's1']), isTrue);
    });

    test('an unknown site forces a refetch', () {
      expect(siteNamesCover(names, ['s1', 's3']), isFalse);
    });

    test('unresolvable (empty) ids never force a refetch', () {
      expect(siteNamesCover(names, ['s1', '']), isTrue);
      expect(siteNamesCover(const {}, ['']), isTrue);
    });

    test('no reports means nothing to resolve', () {
      expect(siteNamesCover(const {}, const []), isTrue);
    });
  });
}
