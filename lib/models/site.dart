import 'enums.dart';

/// An NHVR site (weighbridge, checking station, etc.).
///
/// [currentStatus] is a denormalised/cached convenience value; the source of
/// truth for live status is the recent [SiteReport] stream (see status_logic).
class Site {
  const Site({
    required this.id,
    required this.name,
    required this.type,
    required this.state,
    required this.suburb,
    required this.address,
    this.lat,
    this.lng,
    this.direction,
    this.note,
    this.currentStatus = SiteStatus.open,
    this.openVotes = 0,
    this.blitzVotes = 0,
    this.closedVotes = 0,
    this.lastReportAt,
    this.approved = true,
    this.createdBy,
  });

  final String id;
  final String name;
  final SiteType type;
  final AusState state;
  final String suburb;
  final String address;

  /// Coordinates may be unknown — the authoritative NHVR dataset has none, so
  /// these are filled in by geocoding/community edits. "Nearby" only ranks
  /// sites that have coordinates.
  final double? lat;
  final double? lng;

  /// Optional travel direction, e.g. "northbound" / "southbound".
  final String? direction;

  /// Optional free-text note (e.g. GVM entry requirement, intercept details).
  final String? note;

  final SiteStatus currentStatus;
  final int openVotes;
  final int blitzVotes;
  final int closedVotes;
  final DateTime? lastReportAt;
  final bool approved;
  final String? createdBy;

  /// Build a [Site] from one entry of the bundled seed JSON, given its state
  /// and a stable id (seed entries have no id of their own).
  factory Site.fromSeedJson(
    Map<String, dynamic> json, {
    required AusState state,
    required String id,
  }) {
    return Site(
      id: id,
      name: json['name'] as String,
      type: SiteType.fromJsonValue(json['type'] as String?),
      state: state,
      suburb: json['suburb'] as String? ?? '',
      address: json['address'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      direction: json['direction'] as String?,
      note: json['note'] as String?,
      currentStatus: SiteStatus.fromName(json['currentStatus'] as String?),
    );
  }

  /// Build a [Site] from one station of the authoritative NHVR national
  /// dataset (`sites/nhvr_national_inspection_sites.json`). That schema nests
  /// stations under each state with a shared [facilityType]; coordinates are
  /// absent.
  factory Site.fromNhvrStation(
    Map<String, dynamic> station, {
    required AusState state,
    required String facilityType,
  }) {
    final location = (station['location'] as String? ?? '').trim();
    final suburb = location.split('(').first.trim();
    final route = (station['route'] as String? ?? '').trim();
    final gvm = station['gvm_requirement_tonnes'] as num?;
    final notes = station['notes'] as String?;
    return Site(
      id: station['site_id'] as String,
      name: location.isEmpty ? suburb : location,
      type: _typeFromFacility(facilityType),
      state: state,
      suburb: suburb,
      address: [
        route,
        '$suburb ${state.code}',
      ].where((p) => p.isNotEmpty).join(', '),
      lat: (station['lat'] as num?)?.toDouble(),
      lng: (station['lng'] as num?)?.toDouble(),
      direction: _normaliseDirection(station['direction'] as String?),
      note: gvm != null ? 'Entry required for vehicles ≥ ${gvm}t GVM' : notes,
    );
  }

  static SiteType _typeFromFacility(String facility) {
    final f = facility.toLowerCase();
    if (f.contains('weighbridge')) return SiteType.weighbridge;
    if (f.contains('safety station') || f.contains('hvss')) {
      return SiteType.checkingStation;
    }
    return SiteType.inspection; // PVI, AIS, intercept, etc.
  }

  static String? _normaliseDirection(String? raw) {
    final d = raw?.toLowerCase().trim();
    if (d == 'northbound' || d == 'southbound') return d;
    return null; // "Both" / "N/A" / null → no direction tag
  }

  /// Build a [Site] from a Firestore/document map (id supplied separately).
  factory Site.fromMap(String id, Map<String, dynamic> map) {
    return Site(
      id: id,
      name: map['name'] as String,
      type: SiteType.fromJsonValue(map['type'] as String?),
      state: AusState.fromCode(map['state'] as String? ?? 'NSW'),
      suburb: map['suburb'] as String? ?? '',
      address: map['address'] as String? ?? '',
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      direction: map['direction'] as String?,
      note: map['note'] as String?,
      currentStatus: SiteStatus.fromName(map['currentStatus'] as String?),
      openVotes: (map['openVotes'] as num?)?.toInt() ?? 0,
      blitzVotes: (map['blitzVotes'] as num?)?.toInt() ?? 0,
      closedVotes: (map['closedVotes'] as num?)?.toInt() ?? 0,
      lastReportAt: map['lastReportAt'] != null
          ? DateTime.tryParse(map['lastReportAt'].toString())
          : null,
      approved: map['approved'] as bool? ?? true,
      createdBy: map['createdBy'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type.jsonValue,
      'state': state.code,
      'suburb': suburb,
      'address': address,
      'lat': lat,
      'lng': lng,
      'direction': direction,
      'note': note,
      'currentStatus': currentStatus.name,
      'openVotes': openVotes,
      'blitzVotes': blitzVotes,
      'closedVotes': closedVotes,
      'lastReportAt': lastReportAt?.toIso8601String(),
      'approved': approved,
      'createdBy': createdBy,
    };
  }

  Site copyWith({
    SiteStatus? currentStatus,
    int? openVotes,
    int? blitzVotes,
    int? closedVotes,
    DateTime? lastReportAt,
  }) {
    return Site(
      id: id,
      name: name,
      type: type,
      state: state,
      suburb: suburb,
      address: address,
      lat: lat,
      lng: lng,
      direction: direction,
      note: note,
      currentStatus: currentStatus ?? this.currentStatus,
      openVotes: openVotes ?? this.openVotes,
      blitzVotes: blitzVotes ?? this.blitzVotes,
      closedVotes: closedVotes ?? this.closedVotes,
      lastReportAt: lastReportAt ?? this.lastReportAt,
      approved: approved,
      createdBy: createdBy,
    );
  }
}
