import 'package:flutter/material.dart';

/// Live, community-reported status of a site.
///
/// Only [votable] values are ever **stored** (`currentStatus` on a site,
/// `status` on a report). The other two are display-only and must never reach
/// the wire: every shipped build parses an unknown status string as [open]
/// (see [fromName]), so a new stored value would read as OPEN on phones that
/// cannot be hot-updated.
///
/// * [cameraOnly] — "Camera Only / BGD" (boom gate down, issue #48). A driver
///   can cast it, but it travels as the legacy 'Camera Only' activity report
///   old builds already show, and is derived back into a status client-side
///   (see `status_logic.dart`).
/// * [unknown] — derived when a site has no report within the freshness window
///   (issue #21); never cast.
enum SiteStatus {
  open,
  blitz,
  closed,
  cameraOnly,
  unknown;

  /// The row of three: the statuses with a stored form, cast as real votes.
  static const List<SiteStatus> votable = [open, blitz, closed];

  /// Whether this value may be written to Firestore.
  bool get isStored => votable.contains(this);

  /// Parses a stored status. Only [votable] names are recognised — a
  /// display-only name that somehow landed in a document falls back to [open],
  /// exactly as it does on every shipped build, so all versions agree.
  static SiteStatus fromName(String? value) {
    return votable.firstWhere(
      (s) => s.name == value,
      orElse: () => SiteStatus.open,
    );
  }

  String get label => switch (this) {
    SiteStatus.open => 'Open',
    SiteStatus.blitz => 'Blitz',
    SiteStatus.closed => 'Closed',
    SiteStatus.cameraOnly => 'Camera Only / BGD',
    SiteStatus.unknown => 'Unknown',
  };

  Color get color => switch (this) {
    SiteStatus.open => const Color(0xFF22C55E), // green
    SiteStatus.blitz => const Color(0xFFF59E0B), // amber
    SiteStatus.closed => const Color(0xFFEF4444), // red
    SiteStatus.cameraOnly => const Color(0xFF3B82F6), // blue
    SiteStatus.unknown => const Color(0xFF9A9AA2), // grey
  };
}

/// Kind of NHVR site.
enum SiteType {
  weighbridge,
  checkingStation,
  hvFacility,
  inspection;

  static SiteType fromJsonValue(String? value) {
    return switch (value) {
      'weighbridge' => SiteType.weighbridge,
      'checking_station' => SiteType.checkingStation,
      'hv_facility' => SiteType.hvFacility,
      'inspection' => SiteType.inspection,
      _ => SiteType.inspection,
    };
  }

  String get jsonValue => switch (this) {
    SiteType.weighbridge => 'weighbridge',
    SiteType.checkingStation => 'checking_station',
    SiteType.hvFacility => 'hv_facility',
    SiteType.inspection => 'inspection',
  };

  String get label => switch (this) {
    SiteType.weighbridge => 'Weighbridge',
    SiteType.checkingStation => 'Checking Station',
    SiteType.hvFacility => 'HV Facility',
    SiteType.inspection => 'Inspection',
  };

  IconData get icon => switch (this) {
    SiteType.weighbridge => Icons.scale,
    SiteType.checkingStation => Icons.local_shipping,
    SiteType.hvFacility => Icons.warehouse,
    SiteType.inspection => Icons.fact_check,
  };
}

/// Australian state/territory the app organises sites by.
enum AusState {
  nsw('NSW', 'New South Wales', '🦁'),
  vic('VIC', 'Victoria', '🌿'),
  qld('QLD', 'Queensland', '☀️'),
  sa('SA', 'South Australia', '🌾'),
  wa('WA', 'Western Australia', '🌅'),
  nt('NT', 'Northern Territory', '🐊'),
  tas('TAS', 'Tasmania', '🍎');

  const AusState(this.code, this.fullName, this.emoji);

  final String code;
  final String fullName;
  final String emoji;

  static AusState fromCode(String code) {
    return AusState.values.firstWhere(
      (s) => s.code == code.toUpperCase(),
      orElse: () => AusState.nsw,
    );
  }
}
