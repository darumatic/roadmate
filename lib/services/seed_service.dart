import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'site_repository.dart';

/// One-time seeding of the `sites` collection from the bundled authoritative
/// NHVR dataset. Idempotent: does nothing if the collection already has data.
class SeedService {
  SeedService(
    this.firestore, {
    this.assetPath = 'sites/nhvr_national_inspection_sites.json',
  });

  final FirebaseFirestore firestore;
  final String assetPath;

  Future<void> ensureSeeded() async {
    final sitesCol = firestore.collection('sites');
    final existing = await sitesCol.limit(1).get();
    if (existing.docs.isNotEmpty) return;

    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final sites = parseNhvrNationalData(json);

    final batch = firestore.batch();
    for (final site in sites) {
      batch.set(sitesCol.doc(site.id), {
        ...site.toMap(),
        // Counters/status start fresh; stored map already includes them.
        'lastReportAt': null,
        'seededAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  /// Patch coordinates onto any already-seeded sites that lack them (the
  /// dataset gained geocoded lat/lng after the initial seed). Idempotent: once
  /// every site has coordinates the query is empty, so this becomes a no-op
  /// read. Write failures (e.g. once strict rules are deployed) are ignored.
  Future<void> ensureCoordinates() async {
    final sitesCol = firestore.collection('sites');
    final missing = await sitesCol.where('lat', isNull: true).get();
    if (missing.docs.isEmpty) return;

    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final byId = {for (final s in parseNhvrNationalData(json)) s.id: s};

    try {
      final batch = firestore.batch();
      for (final doc in missing.docs) {
        final site = byId[doc.id];
        if (site?.lat == null) continue;
        batch.update(doc.reference, {'lat': site!.lat, 'lng': site.lng});
      }
      await batch.commit();
    } catch (_) {
      // Coordinates are best-effort; ignore if writes are no longer permitted.
    }
  }
}
