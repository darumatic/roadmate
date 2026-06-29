import 'enums.dart';

enum ActivityReportType {
  longQueue('Long queue'),
  delays('Delays'),
  policePresent('Police present'),
  defectChecks('Defect checks'),
  noActivity('No activity'),
  other('Other');

  const ActivityReportType(this.label);

  final String label;

  static ActivityReportType? fromName(String? name) {
    if (name == null) return null;
    for (final type in ActivityReportType.values) {
      if (type.name == name) return type;
    }
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
    this.uid,
  });

  final String id;
  final String siteId;
  final DateTime createdAt;
  final SiteStatus? status;
  final ActivityReportType? activityType;
  final String? activityNote;
  final String? reporterName;
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
      uid: map['uid'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'siteId': siteId,
      'createdAt': createdAt.toIso8601String(),
      'status': status?.name,
      'activityType': activityType?.name,
      'activityNote': activityNote,
      'reporterName': reporterName,
      'uid': uid,
    };
  }
}
