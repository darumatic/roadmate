import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/proximity_alert.dart';
import 'package:roadmate/services/report_proximity.dart';

void main() {
  // Marulan checking station, roughly.
  const siteLat = -34.71;
  const siteLng = 149.99;

  group('checkReportProximity', () {
    test('a fix inside the radius is allowed', () {
      // ~1.1 km north of the gate.
      expect(
        checkReportProximity(
          siteLat: siteLat,
          siteLng: siteLng,
          position: (lat: -34.70, lng: 149.99),
        ),
        ReportProximity.allowed,
      );
    });

    test('a fix at the gate itself is allowed', () {
      expect(
        checkReportProximity(
          siteLat: siteLat,
          siteLng: siteLng,
          position: (lat: siteLat, lng: siteLng),
        ),
        ReportProximity.allowed,
      );
    });

    test('a fix outside the radius is too far', () {
      // ~5.6 km north.
      expect(
        checkReportProximity(
          siteLat: siteLat,
          siteLng: siteLng,
          position: (lat: -34.66, lng: 149.99),
        ),
        ReportProximity.tooFar,
      );
    });

    test('the boundary is inclusive — exactly at the radius still counts', () {
      // ~1.1 km away with the radius set to exactly that distance: a driver
      // sitting right on the line must not be refused.
      expect(
        checkReportProximity(
          siteLat: siteLat,
          siteLng: siteLng,
          position: (lat: -34.70, lng: siteLng),
          radiusKm: 1.112,
        ),
        ReportProximity.allowed,
      );
      expect(
        checkReportProximity(
          siteLat: siteLat,
          siteLng: siteLng,
          position: (lat: -34.70, lng: siteLng),
          radiusKm: 1.0,
        ),
        ReportProximity.tooFar,
      );
    });

    test('no device position needs location', () {
      expect(
        checkReportProximity(
          siteLat: siteLat,
          siteLng: siteLng,
          position: null,
        ),
        ReportProximity.needsLocation,
      );
    });

    test('an un-geocoded site is always reportable', () {
      // No coordinates means nothing to measure against — refusing would make
      // the site unreportable forever, and asking for location would be asking
      // for something the check cannot use.
      for (final position in [null, (lat: -20.0, lng: 130.0)]) {
        expect(
          checkReportProximity(
            siteLat: null,
            siteLng: null,
            position: position,
          ),
          ReportProximity.allowed,
        );
        expect(
          checkReportProximity(
            siteLat: siteLat,
            siteLng: null,
            position: position,
          ),
          ReportProximity.allowed,
        );
      }
    });
  });

  test('the report radius is the approach-prompt radius', () {
    // The app must never *ask* "what's the status?" at a distance it would
    // then refuse to accept an answer from.
    expect(reportRadiusKm, proximityRadiusKm);
  });

  test('refusal messages name the radius', () {
    expect(kTooFarToReportMessage, contains('3 km'));
    expect(kLocationRequiredMessage, contains('3 km'));
    expect(const TooFarException().toString(), kTooFarToReportMessage);
    expect(
      const LocationRequiredException().toString(),
      kLocationRequiredMessage,
    );
  });
}
