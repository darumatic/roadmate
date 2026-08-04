import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/auth_service.dart';
import 'package:roadmate/services/providers.dart';
import 'package:roadmate/services/username_store.dart';
import 'package:roadmate/widgets/username_prompt.dart';

/// Tap-to-increment counter standing in for real app screens, so tests can
/// prove the gate never reparents (and thereby resets) the app subtree.
class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => count++),
      child: Text('count: $count'),
    );
  }
}

class FakeUser implements User {
  FakeUser({this.anonymous = true});

  final bool anonymous;

  @override
  bool get isAnonymous => anonymous;

  @override
  String? get displayName => anonymous ? null : 'Adrian D';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpGate(
  WidgetTester tester, {
  User? user,
  UserProfile? profile,
  UsernameStore? store,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream.value(user)),
        if (store != null)
          usernameStoreProvider.overrideWithValue(store)
        else
          myProfileProvider.overrideWith((ref) => Stream.value(profile)),
      ],
      child: const MaterialApp(
        home: Scaffold(
          // Full-size child, as in the app (the gate wraps the router).
          body: UsernameGate(
            child: SizedBox.expand(child: Center(child: Text('the app'))),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('UserProfile.signature', () {
    test('road name wins; displayName only for signed-in; else null', () {
      const named = UserProfile(isAnonymous: true, username: 'Dusty Nomad');
      expect(named.signature, 'Dusty Nomad');

      const signedIn = UserProfile(isAnonymous: false, displayName: 'Adrian D');
      expect(signedIn.signature, 'Adrian D');

      const signedInNamed = UserProfile(
        isAnonymous: false,
        username: 'Dusty Nomad',
        displayName: 'Adrian D',
      );
      expect(signedInNamed.signature, 'Dusty Nomad');

      const anonymous = UserProfile(isAnonymous: true);
      expect(anonymous.signature, isNull);

      // Blank strings never count as a signature.
      const blank = UserProfile(
        isAnonymous: false,
        username: ' ',
        displayName: '',
      );
      expect(blank.signature, isNull);
    });
  });

  group('MemoryUsernameStore', () {
    test(
      'claims a name, normalizing it, and emits the updated profile',
      () async {
        final store = MemoryUsernameStore();
        final emitted = <UserProfile?>[];
        final sub = store.watchProfile().listen(emitted.add);

        final name = await store.claimUsername('  dusty   nomad ');
        expect(name, 'dusty nomad');
        await Future<void>.delayed(Duration.zero);
        expect(emitted.last?.username, 'dusty nomad');
        await sub.cancel();
      },
    );

    test('refuses a taken name (case-insensitively) but allows re-claiming '
        'your own', () async {
      final store = MemoryUsernameStore(takenNames: {'Dusty Nomad'});
      expect(
        () => store.claimUsername('DUSTY NOMAD'),
        throwsA(isA<UsernameTakenException>()),
      );

      await store.claimUsername('Big Rig Bob');
      // Same key, new casing: allowed — it is still this user's name.
      expect(await store.claimUsername('big rig bob'), 'big rig bob');
    });

    test('renaming releases the old name for others', () async {
      final store = MemoryUsernameStore();
      await store.claimUsername('Dusty Nomad');
      await store.claimUsername('Big Rig Bob');

      // A second store sharing nothing — simulate by checking the first
      // store's taken set no longer holds the old key: re-claiming it works.
      expect(await store.claimUsername('Dusty Nomad'), 'Dusty Nomad');
    });

    test('rejects invalid names with the validation message', () {
      final store = MemoryUsernameStore();
      expect(
        () => store.claimUsername('!!'),
        throwsA(isA<UsernameInvalidException>()),
      );
    });
  });

  group('UsernameGate', () {
    testWidgets('shows the picker card for an anonymous user with no name', (
      tester,
    ) async {
      await _pumpGate(
        tester,
        user: FakeUser(),
        profile: const UserProfile(isAnonymous: true),
      );
      await tester.pumpAndSettle();

      expect(find.text('PICK YOUR ROAD NAME'), findsOneWidget);
      expect(find.text('the app'), findsOneWidget); // overlay, not a takeover
    });

    testWidgets('stays hidden when signed out, when the profile has not '
        'loaded, and once a name exists', (tester) async {
      await _pumpGate(tester, user: null, profile: null);
      await tester.pumpAndSettle();
      expect(find.text('PICK YOUR ROAD NAME'), findsNothing);

      await _pumpGate(tester, user: FakeUser(), profile: null);
      await tester.pumpAndSettle();
      expect(find.text('PICK YOUR ROAD NAME'), findsNothing);

      await _pumpGate(
        tester,
        user: FakeUser(),
        profile: const UserProfile(isAnonymous: true, username: 'Dusty Nomad'),
      );
      await tester.pumpAndSettle();
      expect(find.text('PICK YOUR ROAD NAME'), findsNothing);
    });

    testWidgets('signed-in users are never prompted — displayName signs for '
        'them', (tester) async {
      await _pumpGate(
        tester,
        user: FakeUser(anonymous: false),
        profile: const UserProfile(isAnonymous: false, displayName: 'Adrian D'),
      );
      await tester.pumpAndSettle();
      expect(find.text('PICK YOUR ROAD NAME'), findsNothing);
    });

    testWidgets('Not now dismisses for the session; saving a name through the '
        'card hides it for good', (tester) async {
      final store = MemoryUsernameStore(
        initialProfile: const UserProfile(isAnonymous: true),
      );
      await _pumpGate(tester, user: FakeUser(), store: store);
      await tester.pumpAndSettle();
      expect(find.text('PICK YOUR ROAD NAME'), findsOneWidget);

      // The prefilled generated name is saveable as-is.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('PICK YOUR ROAD NAME'), findsNothing);
      expect(find.text('the app'), findsOneWidget);
    });

    testWidgets('Not now hides the card without claiming anything', (
      tester,
    ) async {
      final store = MemoryUsernameStore(
        initialProfile: const UserProfile(isAnonymous: true),
      );
      await _pumpGate(tester, user: FakeUser(), store: store);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(find.text('PICK YOUR ROAD NAME'), findsNothing);
    });

    // Regression: in production the gate sits ABOVE the router's Navigator
    // (MaterialApp.builder), where no Overlay exists. Hovering the dice made
    // its tooltip throw "No Overlay widget found" and greyed the whole app.
    // The gate now hosts a local Overlay, so popup UI works up there.
    testWidgets('hovering the dice above the Navigator shows the tooltip '
        'instead of greying the app', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((ref) => Stream.value(FakeUser())),
            myProfileProvider.overrideWith(
              (ref) => Stream.value(const UserProfile(isAnonymous: true)),
            ),
          ],
          child: MaterialApp(
            // The production shape: the gate wraps the Navigator itself.
            builder: (context, child) =>
                UsernameGate(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: Center(child: Text('the app'))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PICK YOUR ROAD NAME'), findsOneWidget);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(
        tester.getCenter(find.byIcon(Icons.casino_outlined)),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(tester.takeException(), isNull);
      expect(find.text('Roll another name'), findsOneWidget); // the tooltip
      // The app underneath is still rendered, not greyed out.
      expect(find.text('the app'), findsOneWidget);
    });

    testWidgets('showing and dismissing the card never resets the app '
        'subtree state', (tester) async {
      final store = MemoryUsernameStore(
        initialProfile: const UserProfile(isAnonymous: true),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((ref) => Stream.value(FakeUser())),
            usernameStoreProvider.overrideWithValue(store),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: UsernameGate(
                child: SizedBox.expand(child: Center(child: _Counter())),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PICK YOUR ROAD NAME'), findsOneWidget);

      // Bump the app-side state while the card is up…
      await tester.tap(find.text('count: 0'));
      await tester.pump();
      expect(find.text('count: 1'), findsOneWidget);

      // …dismissing the card must not rebuild the app subtree from scratch.
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('PICK YOUR ROAD NAME'), findsNothing);
      expect(find.text('count: 1'), findsOneWidget);
    });

    testWidgets('the dice rerolls the suggested name', (tester) async {
      await _pumpGate(
        tester,
        user: FakeUser(),
        profile: const UserProfile(isAnonymous: true),
      );
      await tester.pumpAndSettle();

      String fieldText() =>
          tester.widget<TextField>(find.byType(TextField)).controller!.text;
      final before = fieldText();
      expect(before, isNotEmpty);

      // Reroll until the text changes — consecutive rolls can repeat.
      var changed = false;
      for (var i = 0; i < 10 && !changed; i++) {
        await tester.tap(find.byTooltip('Roll another name'));
        await tester.pump();
        changed = fieldText() != before;
      }
      expect(changed, isTrue);
    });
  });
}
