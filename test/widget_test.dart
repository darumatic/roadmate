import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/app.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site.dart';
import 'package:roadmate/services/startup_service.dart';
import 'package:roadmate/widgets/state_card.dart';
import 'package:roadmate/widgets/status_badge.dart';

void main() {
  testWidgets('RoadMateApp shows startup loading while initializing', (
    tester,
  ) async {
    final startup = Completer<void>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStartupProvider.overrideWith((ref) => startup.future)],
        child: const RoadMateApp(),
      ),
    );

    expect(find.text('RoadMate AU'), findsOneWidget);
    expect(find.text('Know before you roll.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('StatusBadge renders its label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StatusBadge(SiteStatus.blitz))),
    );
    expect(find.text('BLITZ'), findsOneWidget);
  });

  testWidgets('StateCard shows code, name, site count and blitz badge', (
    tester,
  ) async {
    final sites = [
      const Site(
        id: '1',
        name: 'A',
        type: SiteType.weighbridge,
        state: AusState.vic,
        suburb: 'Euroa',
        address: 'Hume Fwy',
        lat: 0,
        lng: 0,
        currentStatus: SiteStatus.blitz,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StateCard(state: AusState.vic, sites: sites),
        ),
      ),
    );
    expect(find.text('VIC'), findsOneWidget);
    expect(find.text('Victoria'), findsOneWidget);
    expect(find.text('1 sites'), findsOneWidget);
    expect(find.text('BLITZ'), findsOneWidget);
  });
}
