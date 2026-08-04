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
