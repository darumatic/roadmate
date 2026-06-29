import 'package:flutter/material.dart';

/// Live, community-reported status of a site.
enum SiteStatus {
  open,
  blitz,
  closed;

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
  };

  Color get color => switch (this) {
    SiteStatus.open => const Color(0xFF22C55E), // green
    SiteStatus.blitz => const Color(0xFFF59E0B), // amber
    SiteStatus.closed => const Color(0xFFEF4444), // red
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
