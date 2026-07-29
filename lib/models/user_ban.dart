import '../services/ban_logic.dart';

/// One `bans/{uid}` document: an admin's suspension of a single user.
///
/// [until] is absent for a permanent ban — see `ban_logic.dart` for why a
/// missing expiry deliberately reads as "still banned".
class UserBan {
  const UserBan({
    required this.uid,
    this.until,
    this.reason,
    this.createdAt,
    this.createdBy,
  });

  final String uid;
  final DateTime? until;
  final String? reason;
  final DateTime? createdAt;

  /// The admin uid that issued it.
  final String? createdBy;

  bool get isPermanent => until == null;

  bool isActiveAt(DateTime now) => banIsActive(until: until, now: now);

  /// Timestamps arrive already normalised to ISO strings by the repositories,
  /// like every other model here.
  factory UserBan.fromMap(String uid, Map<String, dynamic> map) {
    return UserBan(
      uid: uid,
      until: DateTime.tryParse(map['until']?.toString() ?? ''),
      reason: map['reason'] as String?,
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? ''),
      createdBy: map['createdBy'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'until': until?.toIso8601String(),
      'reason': reason,
      'createdAt': createdAt?.toIso8601String(),
      'createdBy': createdBy,
    };
  }
}
