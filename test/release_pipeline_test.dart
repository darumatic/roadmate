import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards the release-pipeline invariants (2026-08-24 rework): web releases
// happen ONLY from the Web Release GitHub Actions pipeline, after every gate
// (CodeQL, Flutter CI, Visual Verification) is green, and store releases are
// a manual workflow_dispatch step behind a green web release. A regression
// here silently changes how production gets deployed, so it fails the local
// suite instead of surfacing minutes into a release.
String _read(String path) => File(path).readAsStringSync();

void main() {
  group('web release pipeline', () {
    test('web-release.yml deploys only behind all three gates', () {
      final wf = _read('.github/workflows/web-release.yml');
      expect(wf, contains('name: Web Release'));
      // A master push is the release trigger.
      expect(wf, contains('push:'));
      expect(wf, contains('branches: [master]'));
      // The deploy job depends on every gate.
      expect(wf, contains('needs: [codeql, flutter-ci, visual-verification]'));
      // The gates run the real reusable workflows, not copies.
      expect(wf, contains('uses: ./.github/workflows/flutter-ci.yml'));
      expect(wf, contains('uses: ./.github/workflows/visual-verification.yml'));
      // The deploy publishes hosting + rules + indexes with the SA secret.
      expect(wf, contains('secrets.FIREBASE_SERVICE_ACCOUNT'));
      expect(wf, contains('--only hosting,firestore:rules,firestore:indexes'));
      expect(wf, contains('./scripts/build_web.sh'));
    });

    test('flutter-ci.yml is callable and no longer double-runs on push', () {
      final wf = _read('.github/workflows/flutter-ci.yml');
      expect(wf, contains('workflow_call:'));
      expect(wf, contains('pull_request:'));
      expect(
        RegExp(r'^\s+push:', multiLine: true).hasMatch(wf),
        isFalse,
        reason:
            'master pushes run inside Web Release; a push trigger here '
            'would run the suite twice per release',
      );
    });

    test('visual verification is a per-push gate, not a nightly cron', () {
      expect(
        File('.github/workflows/nightly-visual.yml').existsSync(),
        isFalse,
        reason: 'renamed to visual-verification.yml',
      );
      final wf = _read('.github/workflows/visual-verification.yml');
      expect(wf, contains('name: Visual Verification'));
      expect(wf, contains('workflow_call:'));
      expect(wf, isNot(contains('schedule:')));
      expect(wf, contains('./scripts/verify_web.sh'));
    });

    test('release.sh never deploys from the terminal', () {
      final sh = _read('scripts/release.sh');
      expect(sh, isNot(contains('firebase deploy')));
      expect(sh, isNot(contains('flutter build web')));
      // The local half of the cycle stays: tests, bump, commit, push.
      expect(sh, contains('flutter test'));
      expect(sh, contains('tool/bump_version.dart'));
      expect(sh, contains('git push'));
    });

    test('release.sh rebases on origin/master before testing and bumping', () {
      // The issue auto-fixer pushes to master unattended, so this workspace
      // goes stale on its own. Bumping on a stale base mints a version the
      // bot already used and the push is rejected only after the whole suite
      // has run (twice on 2026-08-25). The sync must come first.
      final sh = _read('scripts/release.sh');
      expect(sh, contains('git fetch origin'));
      expect(sh, contains('git rebase origin/master'));
      expect(sh.indexOf('git rebase origin/master'),
          lessThan(sh.indexOf('flutter test')));
      expect(sh.indexOf('git rebase origin/master'),
          lessThan(sh.indexOf('tool/bump_version.dart')));
    });

    test('every platform pushes a release alert naming the version', () {
      // Owner request 2026-08-25: notify on a release to ANY platform, with
      // the version number in it. Web is the only one live on delivery; the
      // store scripts must say "submitted", never imply users have it (0.1.72).
      final web = _read('.github/workflows/web-release.yml');
      expect(web, contains('notify_release'));
      expect(web, contains("notify_release('Web'"));
      expect(web, contains('ROADMATE_NTFY_TOPIC'));
      // The version is read from the generated constant, not hard-coded.
      expect(web, contains('lib/version.dart'));

      final play = _read('scripts/play_upload.py');
      expect(play, contains('notify_release('));
      expect(play, contains('NOT live yet'));

      final asc = _read('scripts/asc_submit.py');
      expect(asc, contains('notify_release('));
      expect(asc, contains('NOT live yet'));

      // CI has no ~/.config/roadmate, so the topic arrives as a secret.
      final mobile = _read('.github/workflows/mobile-release.yml');
      expect('ROADMATE_NTFY_TOPIC'.allMatches(mobile).length, 2);
      expect(_read('scripts/setup_release_secrets.sh'), contains('NTFY_TOPIC'));
    });

    test('build_web.sh keeps the deploy guards', () {
      final sh = _read('scripts/build_web.sh');
      expect(sh, contains('--no-tree-shake-icons'));
      // Play's FGS declaration links roadmate.club/fgs-demo.mp4 — the media
      // copy-back must survive (flutter build web silently drops .mp4 files).
      expect(sh, contains('web/*.mp4'));
      // The stale-registrant guard (v1.0.9-v1.0.18 silent web-plugin loss).
      expect(sh, contains('web_plugin_registrant.dart'));
    });

    test('check_ci.sh watches the Web Release pipeline', () {
      expect(_read('scripts/check_ci.sh'), contains('web-release.yml'));
    });
  });

  group('mobile release', () {
    test('mobile-release.yml is manual-only, gated on a green web release', () {
      final wf = _read('.github/workflows/mobile-release.yml');
      expect(wf, contains('workflow_dispatch:'));
      for (final trigger in ['push:', 'pull_request:', 'schedule:']) {
        expect(
          wf,
          isNot(contains('\n  $trigger')),
          reason: 'store releases must never fire automatically',
        );
      }
      expect(
        wf,
        contains('web-release.yml/runs'),
        reason: 'preflight must require a successful Web Release run',
      );
      expect(wf, contains('./scripts/release_android.sh'));
      expect(wf, contains('./scripts/release_ios.sh'));
      expect(wf, contains('RELEASE_DRY_RUN'));
    });

    test('a chosen commit must be on master with its own green Web Release', () {
      final wf = _read('.github/workflows/mobile-release.yml');
      // The Run-workflow dialog's commit picker (empty = latest master) —
      // GitLab-style "release the commit of that green pipeline run".
      expect(wf, contains('commit:'));
      // The preflight ancestry-checks a pasted sha against master...
      expect(wf, contains(r'compare/$sha...master'));
      // ...requires that exact sha's Web Release to be green...
      expect(wf, contains(r'head_sha=$SHA'));
      // ...and both store jobs build exactly the resolved commit.
      expect(
        RegExp(r'needs\.preflight\.outputs\.release_sha').allMatches(wf).length,
        greaterThanOrEqualTo(2),
        reason: 'the android and ios jobs must check out the resolved sha',
      );
    });

    test('store release scripts honour RELEASE_DRY_RUN before any upload', () {
      for (final entry in {
        'scripts/release_android.sh': 'python3 scripts/play_upload.py',
        'scripts/release_ios.sh': 'xcrun altool',
      }.entries) {
        final sh = _read(entry.key);
        final guard = sh.indexOf('RELEASE_DRY_RUN');
        final upload = sh.indexOf(entry.value);
        expect(
          guard,
          greaterThan(0),
          reason: '${entry.key} must support dry runs',
        );
        expect(upload, greaterThan(0));
        expect(
          guard,
          lessThan(upload),
          reason: '${entry.key} must bail out before reaching the upload',
        );
      }
    });

    test('setup_release_secrets.sh covers both machines', () {
      final sh = _read('scripts/setup_release_secrets.sh');
      // Linux (VPS) half: web deploy + Android signing/upload.
      expect(sh, contains('FIREBASE_SERVICE_ACCOUNT'));
      expect(sh, contains('ANDROID_KEYSTORE_BASE64'));
      expect(sh, contains('PLAY_SERVICE_ACCOUNT_JSON'));
      // Mac half: iOS signing + App Store Connect key.
      expect(sh, contains('IOS_DIST_P12_BASE64'));
      expect(sh, contains('ASC_PRIVATE_KEY'));
    });
  });
}
