import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/auth_service.dart';

// Records the calls the controller makes; every member the code under test
// doesn't touch is covered by noSuchMethod.
class FakeFirebaseAuth implements FirebaseAuth {
  User? current;
  Object? popupError;
  int anonSignIns = 0;
  int redirectSignIns = 0;
  int credentialSignIns = 0;
  Object? redirectResultError;
  final revokedCodes = <String>[];

  @override
  User? get currentUser => current;

  @override
  Stream<User?> authStateChanges() => Stream.value(current);

  int popupSignIns = 0;

  @override
  Future<UserCredential> signInWithPopup(AuthProvider provider) async {
    popupSignIns++;
    if (popupError != null) throw popupError!;
    return FakeUserCredential();
  }

  @override
  Future<void> revokeTokenWithAuthorizationCode(
    String authorizationCode,
  ) async {
    revokedCodes.add(authorizationCode);
  }

  @override
  Future<void> signInWithRedirect(AuthProvider provider) async {
    redirectSignIns++;
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    credentialSignIns++;
    return FakeUserCredential();
  }

  @override
  Future<UserCredential> getRedirectResult() async {
    if (redirectResultError != null) throw redirectResultError!;
    return FakeUserCredential();
  }

  @override
  Future<UserCredential> signInAnonymously() async {
    anonSignIns++;
    return FakeUserCredential(fakeUser: FakeUser(fakeUid: 'anon-1'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUser implements User {
  FakeUser({
    this.fakeUid = 'u-1',
    this.anonymous = false,
    this.linkPopupError,
    this.providers = const [],
    this.authorizationCode = 'auth-code-1',
    this.firstDeleteError,
    this.reauthProviderError,
    this.onDelete,
  });

  final String fakeUid;
  final bool anonymous;
  final Object? linkPopupError;
  int linkRedirects = 0;
  int linkPopups = 0;
  final linkedProviders = <AuthProvider>[];

  final List<UserInfo> providers;

  /// Returned via additionalUserInfo on reauthentication credentials.
  final String? authorizationCode;

  /// Thrown by the first delete() call only — models a stale session.
  final Object? firstDeleteError;
  final Object? reauthProviderError;
  final void Function()? onDelete;
  int deleteCalls = 0;
  final reauthProviders = <AuthProvider>[];
  int reauthPopups = 0;

  @override
  String get uid => fakeUid;

  @override
  bool get isAnonymous => anonymous;

  @override
  List<UserInfo> get providerData => providers;

  /// Every forced (`true`) token refresh asked for on this user.
  final tokenRefreshes = <bool>[];

  @override
  Future<String> getIdToken([bool forceRefresh = false]) async {
    tokenRefreshes.add(forceRefresh);
    return 'token';
  }

  @override
  Future<UserCredential> linkWithPopup(AuthProvider provider) async {
    linkPopups++;
    linkedProviders.add(provider);
    if (linkPopupError != null) throw linkPopupError!;
    return FakeUserCredential(fakeUser: this);
  }

  @override
  Future<UserCredential> linkWithProvider(AuthProvider provider) async {
    linkedProviders.add(provider);
    return FakeUserCredential(fakeUser: this);
  }

  @override
  Future<void> linkWithRedirect(AuthProvider provider) async {
    linkRedirects++;
  }

  @override
  Future<void> delete() async {
    deleteCalls++;
    onDelete?.call();
    if (firstDeleteError != null && deleteCalls == 1) throw firstDeleteError!;
  }

  @override
  Future<UserCredential> reauthenticateWithProvider(
    AuthProvider provider,
  ) async {
    reauthProviders.add(provider);
    if (reauthProviderError != null) throw reauthProviderError!;
    return FakeUserCredential(
      additionalInfo: FakeAdditionalUserInfo(code: authorizationCode),
    );
  }

  @override
  Future<UserCredential> reauthenticateWithPopup(AuthProvider provider) async {
    reauthPopups++;
    reauthProviders.add(provider);
    return FakeUserCredential(
      additionalInfo: FakeAdditionalUserInfo(code: authorizationCode),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUserInfo implements UserInfo {
  FakeUserInfo(this.fakeProviderId);

  final String fakeProviderId;

  @override
  String get providerId => fakeProviderId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAdditionalUserInfo implements AdditionalUserInfo {
  FakeAdditionalUserInfo({this.code});

  final String? code;

  @override
  String? get authorizationCode => code;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// user is null by default so syncUser is a no-op and Firestore stays untouched.
class FakeUserCredential implements UserCredential {
  FakeUserCredential({this.fakeUser, this.additionalInfo});

  final User? fakeUser;
  final AdditionalUserInfo? additionalInfo;

  @override
  User? get user => fakeUser;

  @override
  AdditionalUserInfo? get additionalUserInfo => additionalInfo;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Just enough Firestore to observe what deleteAccount erases: doc paths
/// batch-deleted, whether the batch committed, and the seeded favourites the
/// favourites query returns.
class DeletionRecordingFirestore implements FirebaseFirestore {
  DeletionRecordingFirestore({this.favouriteIds = const [], this.onCommit});

  final List<String> favouriteIds;
  final void Function()? onCommit;
  final deletedPaths = <String>[];
  bool committed = false;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _FakeCollection(this, path);

  @override
  WriteBatch batch() => _FakeBatch(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// The cloud_firestore types are @sealed against app-code subclassing; a
// hand-rolled test fake is the intended exception (project convention).
// ignore: subtype_of_sealed_class
class _FakeCollection implements CollectionReference<Map<String, dynamic>> {
  _FakeCollection(this.store, this.collectionPath);

  final DeletionRecordingFirestore store;
  final String collectionPath;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _FakeDoc(store, '$collectionPath/$path');

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => _FakeQuerySnapshot(
    store.favouriteIds
        .map((id) => _FakeQueryDoc(_FakeDoc(store, '$collectionPath/$id')))
        .toList(),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _FakeDoc implements DocumentReference<Map<String, dynamic>> {
  _FakeDoc(this.store, this.docPath);

  final DeletionRecordingFirestore store;
  final String docPath;

  @override
  String get path => docPath;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _FakeCollection(store, '$docPath/$path');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeQuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  _FakeQuerySnapshot(this.fakeDocs);

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> fakeDocs;

  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => fakeDocs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _FakeQueryDoc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _FakeQueryDoc(this.ref);

  final DocumentReference<Map<String, dynamic>> ref;

  @override
  DocumentReference<Map<String, dynamic>> get reference => ref;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBatch implements WriteBatch {
  _FakeBatch(this.store);

  final DeletionRecordingFirestore store;
  final _pending = <String>[];

  @override
  void delete(DocumentReference<Object?> document) {
    _pending.add(document.path);
  }

  @override
  Future<void> commit() async {
    store.deletedPaths.addAll(_pending);
    store.committed = true;
    store.onCommit?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AuthController _controller(
  FakeFirebaseAuth auth, {
  bool isWeb = true,
  bool standalone = false,
  FirebaseFirestore? firestore,
}) => AuthController(
  auth: auth,
  firestore: firestore ?? FakeFirestore(),
  isWeb: isWeb,
  isStandalone: () => standalone,
);

FirebaseAuthException _blocked() => FirebaseAuthException(
  code: 'popup-blocked',
  message: 'Unable to establish a connection with the popup.',
);

void main() {
  group('shouldFallBackToRedirect', () {
    test('true only for popup-blocked', () {
      expect(shouldFallBackToRedirect(_blocked()), isTrue);
      expect(
        shouldFallBackToRedirect(
          FirebaseAuthException(code: 'popup-closed-by-user'),
        ),
        isFalse,
      );
      expect(shouldFallBackToRedirect(Exception('boom')), isFalse);
    });
  });

  group('signInWithGoogle on web', () {
    test('popup success returns the credential without redirecting', () async {
      final auth = FakeFirebaseAuth();
      final credential = await _controller(auth).signInWithGoogle();

      expect(credential, isNotNull);
      expect(auth.popupSignIns, 1);
      expect(auth.redirectSignIns, 0);
    });

    test(
      'installed PWA goes straight to redirect — never opens a popup',
      () async {
        // A PWA "popup" is an opener-less custom tab where the Firebase
        // handler hangs on a blank page (Firefox shortcut-app bug report).
        final auth = FakeFirebaseAuth();
        final credential = await _controller(
          auth,
          standalone: true,
        ).signInWithGoogle();

        expect(credential, isNull);
        expect(auth.popupSignIns, 0);
        expect(auth.redirectSignIns, 1);
      },
    );

    test('installed PWA links the anonymous user via redirect', () async {
      final anon = FakeUser(anonymous: true);
      final auth = FakeFirebaseAuth()..current = anon;

      final credential = await _controller(
        auth,
        standalone: true,
      ).signInWithGoogle();

      expect(credential, isNull);
      expect(anon.linkPopups, 0);
      expect(anon.linkRedirects, 1);
    });

    test('blocked popup falls back to a redirect and returns null', () async {
      final auth = FakeFirebaseAuth()..popupError = _blocked();
      final credential = await _controller(auth).signInWithGoogle();

      expect(credential, isNull);
      expect(auth.redirectSignIns, 1);
    });

    test('other popup errors rethrow instead of silently redirecting', () {
      final auth = FakeFirebaseAuth()
        ..popupError = FirebaseAuthException(code: 'popup-closed-by-user');

      expect(
        () => _controller(auth).signInWithGoogle(),
        throwsA(isA<FirebaseAuthException>()),
      );
      expect(auth.redirectSignIns, 0);
    });

    // The rules decide who may post from the ID token's claims
    // (isRegistered()). Linking keeps the same uid, so a cached token can still
    // look anonymous and refuse the user's very first post after signing in.
    test('linking an anonymous account forces a fresh ID token', () async {
      final anon = FakeUser(anonymous: true);
      final auth = FakeFirebaseAuth()..current = anon;

      await _controller(auth).signInWithGoogle();

      expect(anon.linkPopups, 1);
      expect(anon.tokenRefreshes, [true]);
    });

    test('a native link refreshes the token too', () async {
      final anon = FakeUser(anonymous: true);
      final auth = FakeFirebaseAuth()..current = anon;

      await _controller(auth, isWeb: false).signInWithGoogle();

      expect(anon.tokenRefreshes, [true]);
    });

    test('anonymous user with a blocked popup gets linkWithRedirect', () async {
      final anon = FakeUser(anonymous: true, linkPopupError: _blocked());
      final auth = FakeFirebaseAuth()..current = anon;

      final credential = await _controller(auth).signInWithGoogle();

      expect(credential, isNull);
      expect(anon.linkRedirects, 1);
      expect(auth.redirectSignIns, 0); // linked, not a fresh sign-in
    });
  });

  group('completeRedirectSignIn', () {
    test('no-op off web', () async {
      final auth = FakeFirebaseAuth()
        ..redirectResultError = Exception('must not be called');
      await _controller(auth, isWeb: false).completeRedirectSignIn();
    });

    test('a pending result with no user completes quietly', () async {
      final auth = FakeFirebaseAuth();
      await _controller(auth).completeRedirectSignIn();
      expect(auth.credentialSignIns, 0);
    });

    test(
      'link conflict falls back to signing in with the credential',
      () async {
        final auth = FakeFirebaseAuth()
          ..redirectResultError = FirebaseAuthException(
            code: 'credential-already-in-use',
            credential: GoogleAuthProvider.credential(idToken: 'token'),
          );

        await _controller(auth).completeRedirectSignIn();

        expect(auth.credentialSignIns, 1);
      },
    );

    test('other redirect failures are swallowed', () async {
      final auth = FakeFirebaseAuth()
        ..redirectResultError = FirebaseAuthException(code: 'internal-error');

      await _controller(auth).completeRedirectSignIn();

      expect(auth.credentialSignIns, 0);
    });
  });

  group('signInWithApple', () {
    test(
      'links the anonymous user with the apple.com provider (web)',
      () async {
        final anon = FakeUser(anonymous: true);
        final auth = FakeFirebaseAuth()..current = anon;

        final credential = await _controller(auth).signInWithApple();

        expect(credential, isNotNull);
        expect(anon.linkPopups, 1);
        final provider = anon.linkedProviders.single;
        expect(provider.providerId, 'apple.com');
        expect((provider as AppleAuthProvider).scopes, ['email', 'name']);
      },
    );

    test('links via the native provider flow off web', () async {
      final anon = FakeUser(anonymous: true);
      final auth = FakeFirebaseAuth()..current = anon;

      await _controller(auth, isWeb: false).signInWithApple();

      expect(anon.linkedProviders.single.providerId, 'apple.com');
      expect(anon.linkPopups, 0); // linkWithProvider, not the web popup
    });
  });

  group('deleteAccount', () {
    FakeUserInfo google() => FakeUserInfo('google.com');
    FakeUserInfo apple() => FakeUserInfo('apple.com');

    test('no-op for anonymous or missing users', () async {
      final store = DeletionRecordingFirestore();
      final auth = FakeFirebaseAuth()..current = FakeUser(anonymous: true);

      await _controller(auth, firestore: store).deleteAccount();
      auth.current = null;
      await _controller(auth, firestore: store).deleteAccount();

      expect(store.committed, isFalse);
      expect(auth.anonSignIns, 0);
    });

    test('erases favourites + profile before the auth user, then restores '
        'an anonymous session', () async {
      final events = <String>[];
      final store = DeletionRecordingFirestore(
        favouriteIds: ['site-1', 'site-2'],
        onCommit: () => events.add('firestore'),
      );
      final user = FakeUser(
        providers: [google()],
        onDelete: () => events.add('auth'),
      );
      final auth = FakeFirebaseAuth()..current = user;

      await _controller(auth, isWeb: false, firestore: store).deleteAccount();

      expect(store.deletedPaths, [
        'users/u-1/favourites/site-1',
        'users/u-1/favourites/site-2',
        // Rate-limit ledger (issue #15): erased with the account.
        'users/u-1/limits/actions',
        'users/u-1',
      ]);
      expect(events, ['firestore', 'auth']); // rules need the live uid
      expect(user.deleteCalls, 1);
      expect(auth.anonSignIns, 1);
      expect(auth.revokedCodes, isEmpty); // Google-only: nothing to revoke
      expect(user.reauthProviders, isEmpty);
    });

    test('revokes the Apple token via a fresh reauthentication', () async {
      final user = FakeUser(providers: [apple()]);
      final auth = FakeFirebaseAuth()..current = user;

      await _controller(
        auth,
        isWeb: false,
        firestore: DeletionRecordingFirestore(),
      ).deleteAccount();

      expect(user.reauthProviders.single.providerId, 'apple.com');
      expect(auth.revokedCodes, ['auth-code-1']);
      expect(user.deleteCalls, 1);
      expect(auth.anonSignIns, 1);
    });

    test('a missing authorization code skips revocation but never blocks '
        'the deletion', () async {
      final user = FakeUser(providers: [apple()], authorizationCode: null);
      final auth = FakeFirebaseAuth()..current = user;

      await _controller(
        auth,
        isWeb: false,
        firestore: DeletionRecordingFirestore(),
      ).deleteAccount();

      expect(auth.revokedCodes, isEmpty);
      expect(user.deleteCalls, 1);
      expect(auth.anonSignIns, 1);
    });

    test('a failed Apple reauthentication skips revocation but never blocks '
        'the deletion', () async {
      final user = FakeUser(
        providers: [apple()],
        reauthProviderError: FirebaseAuthException(code: 'user-mismatch'),
      );
      final auth = FakeFirebaseAuth()..current = user;

      await _controller(
        auth,
        isWeb: false,
        firestore: DeletionRecordingFirestore(),
      ).deleteAccount();

      expect(auth.revokedCodes, isEmpty);
      expect(user.deleteCalls, 1);
      expect(auth.anonSignIns, 1);
    });

    test('revocation is skipped on web — firebase_auth only implements it '
        'on Apple platforms', () async {
      final user = FakeUser(providers: [apple()]);
      final auth = FakeFirebaseAuth()..current = user;

      await _controller(
        auth,
        firestore: DeletionRecordingFirestore(),
      ).deleteAccount();

      expect(user.reauthProviders, isEmpty);
      expect(auth.revokedCodes, isEmpty);
      expect(user.deleteCalls, 1);
    });

    test('requires-recent-login reauthenticates with the linked provider '
        'and retries (native)', () async {
      final user = FakeUser(
        providers: [google()],
        firstDeleteError: FirebaseAuthException(code: 'requires-recent-login'),
      );
      final auth = FakeFirebaseAuth()..current = user;

      await _controller(
        auth,
        isWeb: false,
        firestore: DeletionRecordingFirestore(),
      ).deleteAccount();

      expect(user.reauthProviders.single, isA<GoogleAuthProvider>());
      expect(user.reauthPopups, 0);
      expect(user.deleteCalls, 2);
      expect(auth.anonSignIns, 1);
    });

    test('requires-recent-login reauthenticates via popup on web', () async {
      final user = FakeUser(
        providers: [google()],
        firstDeleteError: FirebaseAuthException(code: 'requires-recent-login'),
      );
      final auth = FakeFirebaseAuth()..current = user;

      await _controller(
        auth,
        firestore: DeletionRecordingFirestore(),
      ).deleteAccount();

      expect(user.reauthPopups, 1);
      expect(user.deleteCalls, 2);
      expect(auth.anonSignIns, 1);
    });

    test('a stale session right after the Apple reauth rethrows instead of '
        'looping', () async {
      final user = FakeUser(
        providers: [apple()],
        firstDeleteError: FirebaseAuthException(code: 'requires-recent-login'),
      );
      final auth = FakeFirebaseAuth()..current = user;

      await expectLater(
        _controller(
          auth,
          isWeb: false,
          firestore: DeletionRecordingFirestore(),
        ).deleteAccount(),
        throwsA(isA<FirebaseAuthException>()),
      );
      expect(user.deleteCalls, 1);
      expect(auth.anonSignIns, 0); // never resurrect a failed deletion
    });

    test(
      'other delete failures propagate without an anonymous sign-in',
      () async {
        final user = FakeUser(
          providers: [google()],
          firstDeleteError: FirebaseAuthException(code: 'internal-error'),
        );
        final auth = FakeFirebaseAuth()..current = user;

        await expectLater(
          _controller(
            auth,
            isWeb: false,
            firestore: DeletionRecordingFirestore(),
          ).deleteAccount(),
          throwsA(isA<FirebaseAuthException>()),
        );
        expect(user.reauthProviders, isEmpty);
        expect(auth.anonSignIns, 0);
      },
    );
  });

  group('ensureSignedIn', () {
    test(
      'keeps a restored session instead of signing in anonymously',
      () async {
        final auth = FakeFirebaseAuth()
          ..current = FakeUser(fakeUid: 'google-1');

        expect(await ensureSignedIn(auth), 'google-1');
        expect(auth.anonSignIns, 0);
      },
    );

    test('signs in anonymously when nobody is restored', () async {
      final auth = FakeFirebaseAuth();

      expect(await ensureSignedIn(auth), 'anon-1');
      expect(auth.anonSignIns, 1);
    });
  });
}
