import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/models/site_report.dart';
import 'package:roadmate/services/admin_repository.dart';

void main() {
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
