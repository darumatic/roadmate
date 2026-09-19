import 'enums.dart';

enum ActivityReportType {
  longQueue('Long queue', 'longQueue'),
  delays('Delays', 'delays'),
  policePresent('Police present', 'policePresent'),
  defectChecks('BGD', 'BGD'),
  noActivity('Camera Only', 'Camera Only'),
  other('Other', 'other');

  const ActivityReportType(this.label, this.wire);

  final String label;

  /// Value written to Firestore — must be in the `activityType` allow-list in
  /// firestore.rules ('BGD'/'Camera Only' there per issue #4).
  final String wire;

  /// The types the "Report activity" dialog offers. BGD and Camera Only left
  /// it when they became the Camera Only / BGD status button (issue #48); the
  /// enum values stay, because shipped builds still post them and every build
  /// must keep parsing, listing and (for admins) editing those reports.
  static const List<ActivityReportType> reportable = [
    longQueue,
    delays,
    policePresent,
    other,
  ];

  /// Whether a report of this type says "Camera Only / BGD" — which builds
  /// that know the fourth status read as that status (see `status_logic.dart`).
  bool get meansCameraOnly => this == noActivity || this == defectChecks;

  static ActivityReportType? fromName(String? name) {
    if (name == null) return null;
    for (final type in ActivityReportType.values) {
      // Accept the wire value and the Dart enum name (documents written
      // before the issue-#4 rename stored 'defectChecks'/'noActivity').
      if (type.wire == name || type.name == name) return type;
    }
    if (name == 'CameraOnly') return ActivityReportType.noActivity;
    return null;
  }
}

/// The document an activity report is stored as — the exact shape
/// `isValidActivityReport` in firestore.rules accepts, and the one every
/// shipped build reads. Absent values are left out rather than written as
/// null (the rules type-check each optional key). Pure: [serverTime] is
/// injected (`FieldValue.serverTimestamp()` in production) so the wire shape is
/// unit-testable, which matters more than usual here — a Camera Only / BGD
/// press is *defined* as this document, byte for byte.
Map<String, Object> activityReportPayload({
  required String siteId,
  required String uid,
  required ActivityReportType type,
  required int reporterLevel,
  required Object serverTime,
  String? note,
  String? reporterName,
}) {
  final trimmedNote = note?.trim();
  final trimmedName = reporterName?.trim();
  return {
    'siteId': siteId,
    'activityType': type.wire,
    'uid': uid,
    'createdAt': serverTime,
    if (trimmedNote != null && trimmedNote.isNotEmpty)
      'activityNote': trimmedNote,
    if (trimmedName != null && trimmedName.isNotEmpty)
      'reporterName': trimmedName,
    // The author's level after this post, denormalized into the doc so
    // report rows can show it without any per-author read.
    'reporterLevel': reporterLevel,
  };
}

/// A single community report about a site: either a status vote
/// (open/blitz/closed) and/or a free-text activity note.
class SiteReport {
  const SiteReport({
    required this.id,
    required this.siteId,
    required this.createdAt,
    this.status,
    this.activityType,
    this.activityNote,
    this.reporterName,
    this.reporterLevel,
    this.uid,
  });

  final String id;
  final String siteId;
  final DateTime createdAt;
  final SiteStatus? status;
  final ActivityReportType? activityType;
  final String? activityNote;
  final String? reporterName;

  /// The author's participation level (1-based ladder index), denormalized
  /// into the doc at write time so report rows can show a level icon without
  /// any per-author profile read. Absent on docs from older clients.
  final int? reporterLevel;

  final String? uid;

  bool get isActivityReport => activityType != null;

  factory SiteReport.fromMap(String id, Map<String, dynamic> map) {
    return SiteReport(
      id: id,
      siteId: map['siteId'] as String,
      createdAt:
          DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      status: map['status'] != null
          ? SiteStatus.fromName(map['status'] as String?)
          : null,
      activityType: ActivityReportType.fromName(map['activityType'] as String?),
      activityNote: map['activityNote'] as String?,
      reporterName: map['reporterName'] as String?,
      reporterLevel: (map['reporterLevel'] as num?)?.toInt(),
      uid: map['uid'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'siteId': siteId,
      'createdAt': createdAt.toIso8601String(),
      'status': status?.name,
      'activityType': activityType?.wire,
      'activityNote': activityNote,
      'reporterName': reporterName,
      'reporterLevel': reporterLevel,
      'uid': uid,
    };
  }
}
