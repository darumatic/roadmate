import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/admin_repository.dart';

void main() {
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
