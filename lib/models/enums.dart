import 'package:flutter/material.dart';

/// Live, community-reported status of a site.
///
/// [unknown] is display-only (issue #21): it is derived when a site has no
/// report within the freshness window and is never stored or voted, so it is
/// not part of [votable].
enum SiteStatus {
  open,
  blitz,
  closed,
  unknown;

  /// Statuses a driver can vote for — [unknown] is derived, never cast.
  static const List<SiteStatus> votable = [open, blitz, closed];

  static SiteStatus fromName(String? value) {
    return SiteStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => SiteStatus.open,
    );
  }

  String get label => switch (this) {
    SiteStatus.open => 'Open',
    SiteStatus.blitz => 'Blitz',
    SiteStatus.closed => 'Closed',
    SiteStatus.unknown => 'Unknown',
  };

  Color get color => switch (this) {
    SiteStatus.open => const Color(0xFF22C55E), // green
    SiteStatus.blitz => const Color(0xFFF59E0B), // amber
    SiteStatus.closed => const Color(0xFFEF4444), // red
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
