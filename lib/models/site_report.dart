import 'enums.dart';

/// A single community report about a site: either a status vote
/// (open/blitz/closed) and/or a free-text activity note.
class SiteReport {
  const SiteReport({
    required this.id,
    required this.siteId,
    required this.createdAt,
    this.status,
    this.activityNote,
    this.uid,
  });

  final String id;
  final String siteId;
  final DateTime createdAt;
  final SiteStatus? status;
  final String? activityNote;
  final String? uid;

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
      activityNote: map['activityNote'] as String?,
      uid: map['uid'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'siteId': siteId,
      'createdAt': createdAt.toIso8601String(),
      'status': status?.name,
      'activityNote': activityNote,
      'uid': uid,
    };
  }
}
