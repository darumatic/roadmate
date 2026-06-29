import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site.dart';
import 'package:roadmate/services/site_stats.dart';

Site _site({
  required String id,
  required AusState state,
  SiteStatus status = SiteStatus.open,
  String name = 'Site',
  String suburb = 'Town',
}) {
  return Site(
    id: id,
    name: name,
    type: SiteType.weighbridge,
    state: state,
    suburb: suburb,
    address: '$suburb Rd',
    lat: 0,
    lng: 0,
    currentStatus: status,
  );
}

void main() {
  final sites = [
    _site(id: '1', state: AusState.nsw, status: SiteStatus.open),
    _site(id: '2', state: AusState.nsw, status: SiteStatus.blitz),
    _site(id: '3', state: AusState.vic, status: SiteStatus.closed),
    _site(id: '4', state: AusState.vic, status: SiteStatus.open, name: 'Euroa'),
  ];

  test('countByStatus tallies each status', () {
    final c = countByStatus(sites);
    expect(c.open, 2);
    expect(c.blitz, 1);
    expect(c.closed, 1);
    expect(c.total, 4);
  });

  test('groupByState includes all states and groups correctly', () {
    final grouped = groupByState(sites);
    expect(grouped.keys.length, AusState.values.length);
    expect(grouped[AusState.nsw]!.length, 2);
    expect(grouped[AusState.vic]!.length, 2);
    expect(grouped[AusState.qld]!, isEmpty);
  });

  test('blitzSites returns only blitz-status sites', () {
    final result = blitzSites(sites);
    expect(result.length, 1);
    expect(result.first.currentStatus, SiteStatus.blitz);
  });

  test('recentlyActive sorts by lastReportAt desc and excludes inactive', () {
    final active = [
      _site(
        id: 'a',
        state: AusState.nsw,
      ).copyWith(lastReportAt: DateTime(2026, 6, 29, 9)),
      _site(
        id: 'b',
        state: AusState.vic,
      ).copyWith(lastReportAt: DateTime(2026, 6, 29, 11)),
      _site(id: 'c', state: AusState.qld), // no activity
    ];
    final result = recentlyActive(active);
    expect(result.map((s) => s.id), ['b', 'a']);
  });

  group('searchSites', () {
    test('empty query returns all', () {
      expect(searchSites(sites, '   ').length, sites.length);
    });

    test('matches by name', () {
      final result = searchSites(sites, 'euroa');
      expect(result.length, 1);
      expect(result.first.name, 'Euroa');
    });

    test('matches by state code', () {
      expect(searchSites(sites, 'vic').length, 2);
    });
  });
}
