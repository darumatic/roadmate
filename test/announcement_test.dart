import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/announcement.dart';

void main() {
  final published = DateTime.utc(2026, 7, 30, 9);

  Map<String, dynamic> raw({
    String message = 'Roadworks on the Hume from Monday.',
    String? severity = 'info',
    String? expiresAt,
  }) {
    return {
      'message': message,
      'severity': severity,
      'publishedAt': published.toIso8601String(),
      'publishedBy': 'admin1',
      'expiresAt': expiresAt,
    };
  }

  group('Announcement.fromMap', () {
    test('parses a published notice', () {
      final announcement = Announcement.fromMap(raw())!;
      expect(announcement.message, 'Roadworks on the Hume from Monday.');
      expect(announcement.severity, AnnouncementSeverity.info);
      expect(announcement.publishedAt, published);
      expect(announcement.publishedBy, 'admin1');
      expect(announcement.expiresAt, isNull);
    });

    test('reads the warning severity', () {
      expect(
        Announcement.fromMap(raw(severity: 'warning'))!.severity,
        AnnouncementSeverity.warning,
      );
    });

    test('an unknown or missing severity falls back to info', () {
      // Additive-change guarantee: a newer admin build using a level this
      // client has never heard of must still show the message.
      expect(
        Announcement.fromMap(raw(severity: 'critical'))!.severity,
        AnnouncementSeverity.info,
      );
      expect(
        Announcement.fromMap(raw(severity: null))!.severity,
        AnnouncementSeverity.info,
      );
    });

    test('a missing, blank or absent message yields no notice', () {
      // A half-written doc must never render an empty banner.
      expect(Announcement.fromMap(null), isNull);
      expect(Announcement.fromMap({}), isNull);
      expect(Announcement.fromMap(raw(message: '   ')), isNull);
    });

    test('trims the message', () {
      expect(Announcement.fromMap(raw(message: '  hi  '))!.message, 'hi');
    });
  });

  group('isVisibleAt', () {
    test('a notice with no expiry stays up', () {
      final announcement = Announcement.fromMap(raw())!;
      expect(
        announcement.isVisibleAt(published.add(const Duration(days: 90))),
        isTrue,
      );
    });

    test('hides once the expiry passes', () {
      final expiry = published.add(const Duration(days: 7));
      final announcement = Announcement.fromMap(
        raw(expiresAt: expiry.toIso8601String()),
      )!;
      expect(
        announcement.isVisibleAt(expiry.subtract(const Duration(minutes: 1))),
        isTrue,
      );
      // Boundary: at the expiry instant it is already gone.
      expect(announcement.isVisibleAt(expiry), isFalse);
      expect(
        announcement.isVisibleAt(expiry.add(const Duration(minutes: 1))),
        isFalse,
      );
    });

    test('hides once this exact notice has been dismissed', () {
      final announcement = Announcement.fromMap(raw())!;
      expect(
        announcement.isVisibleAt(
          published,
          dismissedKey: announcement.dismissKey,
        ),
        isFalse,
      );
    });

    test('an edited notice re-shows to someone who dismissed the old one', () {
      // Dismissal is keyed on publishedAt, so republishing reaches everyone
      // again — including people who had closed the previous message.
      final old = Announcement.fromMap(raw())!;
      final edited = Announcement(
        message: 'Corrected message.',
        publishedAt: published.add(const Duration(hours: 1)),
      );
      expect(
        edited.isVisibleAt(published, dismissedKey: old.dismissKey),
        isTrue,
      );
    });

    test('a notice with no server stamp yet is dismissable by message', () {
      const announcement = Announcement(message: 'local echo');
      expect(announcement.dismissKey, 'message:local echo');
      expect(
        announcement.isVisibleAt(published, dismissedKey: 'message:local echo'),
        isFalse,
      );
    });
  });

  group('editData', () {
    test('carries message, severity and expiry', () {
      final expiry = published.add(const Duration(days: 7));
      final data = Announcement.editData(
        message: '  Blitz season starts Monday.  ',
        severity: AnnouncementSeverity.warning,
        expiresAt: expiry,
      );
      expect(data, {
        'message': 'Blitz season starts Monday.',
        'severity': 'warning',
        'expiresAt': expiry,
      });
    });

    test('omits the expiry entirely when there is none', () {
      // Absent, not null: the key allow-list in isValidAnnouncement accepts a
      // missing expiresAt but not a null one.
      final data = Announcement.editData(
        message: 'hi',
        severity: AnnouncementSeverity.info,
      );
      expect(data.containsKey('expiresAt'), isFalse);
    });

    test('truncates a message past the cap the rules enforce', () {
      final data = Announcement.editData(
        message: 'x' * (kAnnouncementMaxLength + 40),
        severity: AnnouncementSeverity.info,
      );
      expect((data['message']! as String).length, kAnnouncementMaxLength);
    });
  });
}
