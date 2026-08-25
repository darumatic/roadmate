/// Admin → all users broadcast: one short message shown as a banner across the
/// top of every screen (or, when it asks for a store rating, as a popup).
///
/// **One document, `announcements/current`.** A single-doc snapshot listener is
/// the cheapest thing Firestore offers — one read when a client opens the app,
/// one more each time an admin changes the message — which is why this is not a
/// collection query or a per-user fan-out (see the read-budget note in
/// CLAUDE.md). Publishing overwrites the doc; clearing deletes it.
///
/// Reads are public in `firestore.rules`, exactly like `config/app`, so the
/// banner works for anonymous users and before sign-in has settled.
///
/// **Expiry is client-side.** An admin may set `expiresAt`, and every client
/// hides the notice once it passes — the same reasoning as the 10h status
/// freshness window: behaviour that might change lives in client logic rather
/// than in rules that already-shipped mobile builds must keep satisfying.
///
/// Delivery is in-app only. RoadMate has no push channel
/// (`flutter_local_notifications` is device-local, for the approach prompt), so
/// a notice is seen the next time someone opens the app.
library;

import 'notice_markup.dart';

/// Longest message an admin may publish — mirrors the 280-char cap in
/// `firestore.rules` (isValidAnnouncement).
const int kAnnouncementMaxLength = 280;

/// Longest rich-markup source (`messageHtml`) — larger than the plain cap
/// because tags cost characters without adding visible text. Mirrors the
/// 480-char cap in `firestore.rules`.
const int kAnnouncementHtmlMaxLength = 480;

/// The one `cta` value defined so far: ask the reader to rate the app in
/// their platform's store. A string (not a bool) so later CTAs stay additive
/// exactly like [AnnouncementSeverity] levels.
const String kAnnouncementCtaRate = 'rate';

/// How loud the banner is. Stored as the wire string, so adding a level later
/// stays additive for old clients (they fall back to [info]).
enum AnnouncementSeverity {
  info('info'),
  warning('warning');

  const AnnouncementSeverity(this.wire);

  final String wire;

  /// Unknown or missing values read as [info]: a client must never drop a
  /// message just because a newer admin build used a level it doesn't know.
  static AnnouncementSeverity fromWire(String? wire) {
    return AnnouncementSeverity.values.firstWhere(
      (severity) => severity.wire == wire,
      orElse: () => AnnouncementSeverity.info,
    );
  }
}

/// One `announcements/current` document.
class Announcement {
  const Announcement({
    required this.message,
    this.messageHtml,
    this.color,
    this.severity = AnnouncementSeverity.info,
    this.cta,
    this.publishedAt,
    this.publishedBy,
    this.expiresAt,
  });

  final String message;

  /// Rich source in the safe HTML subset of `notice_markup.dart`, when the
  /// admin used any markup. [message] always carries the plain-text rendering
  /// of the same notice — that is what pre-rich clients (0.1.55–0.1.67 mobile
  /// builds) show, so the two must tell the same story.
  final String? messageHtml;

  /// `#RRGGBB` background override, or null to colour by [severity]. Kept as
  /// the wire string; [colorValue] is the parsed form.
  final String? color;

  final AnnouncementSeverity severity;

  /// Optional call-to-action, kept as the wire string ([kAnnouncementCtaRate]
  /// is the only value so far). An unknown value from a newer admin build
  /// renders as a plain notice — a CTA must never cost anyone the message.
  final String? cta;

  /// Whether this notice asks the reader to rate the app — shown as a popup
  /// (`RateAppPopup`) rather than a banner from 1.0.12. The gate hides such a
  /// notice entirely on platforms with no store to rate in (web, desktop);
  /// mobile builds 0.1.55–0.1.73 show just the text, without the button, and
  /// 0.1.74–1.0.11 the banner with its button.
  bool get asksForRating => cta == kAnnouncementCtaRate;

  /// [color] as opaque ARGB, or null when unset (invalid values were already
  /// dropped in [fromMap]).
  int? get colorValue => parseHexColor(color);

  /// When an admin published it. Doubles as the notice's identity: dismissal is
  /// remembered per [publishedAt], so editing the message re-shows the banner to
  /// everyone who had dismissed the previous one.
  final DateTime? publishedAt;

  /// The publishing admin's uid.
  final String? publishedBy;

  /// Optional auto-hide time.
  final DateTime? expiresAt;

  /// Timestamps arrive already normalised to ISO strings by the repositories,
  /// like every other model here. A doc with no usable message yields null —
  /// a half-written notice must not render an empty banner.
  static Announcement? fromMap(Map<String, dynamic>? map) {
    final message = (map?['message'] as String?)?.trim();
    if (message == null || message.isEmpty) return null;
    final messageHtml = (map?['messageHtml'] as String?)?.trim();
    final color = map?['color'] as String?;
    return Announcement(
      message: message,
      // Blank markup or an unparseable colour degrade to the plain notice
      // rather than suppressing it — additive fields must never cost a message.
      messageHtml: (messageHtml?.isEmpty ?? true) ? null : messageHtml,
      color: parseHexColor(color) == null ? null : color,
      severity: AnnouncementSeverity.fromWire(map?['severity'] as String?),
      cta: map?['cta'] as String?,
      publishedAt: DateTime.tryParse(map?['publishedAt']?.toString() ?? ''),
      publishedBy: map?['publishedBy'] as String?,
      expiresAt: DateTime.tryParse(map?['expiresAt']?.toString() ?? ''),
    );
  }

  /// The key dismissal is remembered under. Falls back to the message itself
  /// when a notice has no server timestamp yet (the brief window between a
  /// local write and the server's echo), so dismissal still sticks.
  String get dismissKey =>
      publishedAt?.toUtc().toIso8601String() ?? 'message:$message';

  /// Whether the banner should be on screen at [now].
  ///
  /// Hidden once [expiresAt] passes, or once this exact notice has been
  /// dismissed on this device ([dismissedKey] is what was stored).
  bool isVisibleAt(DateTime now, {String? dismissedKey}) {
    if (dismissedKey != null && dismissedKey == dismissKey) return false;
    final expiry = expiresAt;
    if (expiry != null && !expiry.isAfter(now)) return false;
    return true;
  }

  /// Field values for a published notice, minus the server-stamped bookkeeping
  /// the repository adds (`publishedAt`/`publishedBy`). Pure, so the shape the
  /// rules validate is unit-testable without Firestore — same split as
  /// `banEditData` in `ban_logic.dart`. Over-long messages are truncated rather
  /// than rejected here; the admin form caps the field too.
  static Map<String, Object> editData({
    required String message,
    String? messageHtml,
    required AnnouncementSeverity severity,
    String? color,
    String? cta,
    DateTime? expiresAt,
  }) {
    final trimmed = message.trim();
    final richTrimmed = messageHtml?.trim();
    return {
      'message': trimmed.length > kAnnouncementMaxLength
          ? trimmed.substring(0, kAnnouncementMaxLength)
          : trimmed,
      // Absent, not null/empty, when the notice is plain — so a plain publish
      // stays byte-identical to the pre-rich write shape.
      if (richTrimmed != null && richTrimmed.isNotEmpty)
        'messageHtml': richTrimmed.length > kAnnouncementHtmlMaxLength
            ? richTrimmed.substring(0, kAnnouncementHtmlMaxLength)
            : richTrimmed,
      // Only a colour the rules would accept; anything else falls back to the
      // severity colour rather than failing the whole publish.
      if (parseHexColor(color) != null) 'color': color!,
      // Absent (not null) for an ordinary notice — same discipline as
      // messageHtml, so a plain publish keeps the pre-CTA write shape.
      if (cta == kAnnouncementCtaRate) 'cta': cta!,
      'severity': severity.wire,
      'expiresAt': ?expiresAt,
    };
  }
}
