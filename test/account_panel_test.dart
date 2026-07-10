import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/auth_service.dart';
import 'package:roadmate/widgets/account_panel.dart';

class FakeAuthController implements AuthController {
  int appleSignIns = 0;
  int googleSignIns = 0;
  int signOuts = 0;
  int deleteCalls = 0;

  @override
  Future<UserCredential?> signInWithApple() async {
    appleSignIns++;
    return FakeUserCredential();
  }

  @override
  Future<UserCredential?> signInWithGoogle() async {
    googleSignIns++;
    return FakeUserCredential();
  }

  @override
  Future<void> signOut() async {
    signOuts++;
  }

  @override
  Future<void> deleteAccount() async {
    deleteCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUserCredential implements UserCredential {
  @override
  User? get user => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUser implements User {
  FakeUser({this.anonymous = false});

  final bool anonymous;

  @override
  bool get isAnonymous => anonymous;

  @override
  String? get email => 'truckie@example.com';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<FakeAuthController> _pump(WidgetTester tester, {User? user}) async {
  final controller = FakeAuthController();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authControllerProvider.overrideWithValue(controller)],
      child: MaterialApp(
        home: Scaffold(body: AccountActions(user: user)),
      ),
    ),
  );
  return controller;
}

void main() {
  group('AccountActions sign-in buttons', () {
    testWidgets('Apple button shows on iOS above Google and signs in', (
      tester,
    ) async {
      // Must be reset before the test body ends — the binding asserts all
      // foundation debug variables are back to their defaults.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final controller = await _pump(tester, user: FakeUser(anonymous: true));

      final apple = tester.getTopLeft(find.text('Sign in with Apple'));
      final google = tester.getTopLeft(find.text('Sign in with Google'));
      expect(apple.dy, lessThan(google.dy));

      await tester.tap(find.text('Sign in with Apple'));
      await tester.pumpAndSettle();
      expect(controller.appleSignIns, 1);
      expect(controller.googleSignIns, 0);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Google button gets the same filled style as Apple', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await _pump(tester, user: FakeUser(anonymous: true));

      final buttons = tester
          .widgetList<FilledButton>(find.bySubtype<FilledButton>())
          .toList();
      expect(buttons, hasLength(2), reason: 'both providers use FilledButton');
      Color? backgroundOf(FilledButton button) =>
          button.style?.backgroundColor?.resolve(const {});
      Color? foregroundOf(FilledButton button) =>
          button.style?.foregroundColor?.resolve(const {});
      expect(buttons.map(backgroundOf), everyElement(Colors.black));
      expect(buttons.map(foregroundOf), everyElement(Colors.white));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('no Apple button off iOS — web/Android stay Google-only', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await _pump(tester, user: null);

      expect(find.text('Sign in with Apple'), findsNothing);
      expect(find.text('Sign in with Google'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('signed-in users see sign out and delete, not sign in', (
      tester,
    ) async {
      await _pump(tester, user: FakeUser());

      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Delete account'), findsOneWidget);
      expect(find.textContaining('Sign in with'), findsNothing);
    });

    testWidgets('anonymous users get no delete-account button', (tester) async {
      await _pump(tester, user: FakeUser(anonymous: true));

      expect(find.text('Delete account'), findsNothing);
    });
  });

  group('AccountActions delete flow', () {
    testWidgets('deleting asks for confirmation and discloses what remains', (
      tester,
    ) async {
      final controller = await _pump(tester, user: FakeUser());

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();

      expect(find.text('Delete account?'), findsOneWidget);
      expect(find.textContaining('anonymised'), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);
      expect(controller.deleteCalls, 0); // nothing until confirmed
    });

    testWidgets('cancel closes the dialog without deleting', (tester) async {
      final controller = await _pump(tester, user: FakeUser());

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Delete account?'), findsNothing);
      expect(controller.deleteCalls, 0);
    });

    testWidgets('confirming runs the deletion exactly once', (tester) async {
      final controller = await _pump(tester, user: FakeUser());

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Delete account'),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.deleteCalls, 1);
      expect(find.text('Your account has been deleted.'), findsOneWidget);
    });
  });
}
