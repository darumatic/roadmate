import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The issue auto-fixer (scripts/fix_issues.py) can push straight to master —
/// which auto-deploys web — so its guard logic is tested by a stdlib Python
/// suite (`scripts/fix_issues_test.py`); this test runs that suite as part of
/// `flutter test`, and pins the source-level invariants that keep the bot
/// safe (see specs.md "Issue auto-fixer").
void main() {
  test('fix_issues.py self-test suite passes', () {
    final result = Process.runSync('python3', [
      'scripts/fix_issues_test.py',
    ], workingDirectory: Directory.current.path);
    expect(
      result.exitCode,
      0,
      reason:
          'scripts/fix_issues_test.py failed:\n'
          '${result.stdout}\n${result.stderr}',
    );
  });

  test('notify.py self-test suite passes', () {
    final result = Process.runSync('python3', [
      'scripts/notify_test.py',
    ], workingDirectory: Directory.current.path);
    expect(
      result.exitCode,
      0,
      reason:
          'scripts/notify_test.py failed:\n'
          '${result.stdout}\n${result.stderr}',
    );
  });

  test('runner keeps its security invariants', () {
    final script = File('scripts/fix_issues.py').readAsStringSync();
    // Only the owner may approve; widening this list is an owner decision.
    expect(script, contains("ALLOWED_APPROVERS = ['deccico']"));
    // The owner-facing trigger label is plain "approved" (owner's choice).
    expect(script, contains("LABEL_APPROVED = 'approved'"));
    // Runs headless as the (non-root) personal user; the IS_SANDBOX root
    // bypass must never reappear.
    expect(script, contains('--dangerously-skip-permissions'));
    expect(script, isNot(contains('IS_SANDBOX')));
    // Attribution defenses: settings flag + the clone's commit-msg hook.
    expect(script, contains('"includeCoAuthoredBy": false'));
    // The bot releases only through the house release cycle and watches the
    // pipeline; it never deploys directly.
    expect(script, contains('check_ci.sh'));
    expect(script, contains('NEVER run `firebase deploy`'));
    expect(script, contains('./scripts/release.sh'));
    // The supervisor closes the issue after a green pipeline; Claude must not
    // let GitHub auto-close it early via commit keywords.
    expect(script, contains('Never use closing keywords'));
    // The untrusted-input fence and the zero-write evaluation mode.
    expect(script, contains('<<<ISSUE-DATA'));
    expect(script, contains('--dry-run'));
    // Web tools stay off in headless runs.
    expect(script, contains("DISALLOWED_TOOLS = 'WebFetch,WebSearch'"));
    // Model + spend pin (owner decision, 2026-08-25): 'fable' at max effort
    // billed \$9.59 for ONE issue and emptied the credit pool ~50 min later,
    // stalling every approved issue behind it. The bot runs opus/xhigh under a
    // daily cap; the polling tick itself never invokes Claude.
    expect(script, contains("CLAUDE_MODEL = 'opus'"));
    expect(script, contains("CLAUDE_EFFORT = 'xhigh'"));
    expect(script, contains('DAILY_BUDGET_USD = 10.0'));
    // A runner outage (429 / 5xx) must DEFER and retry, never be filed as a
    // verdict on the issue — that burned four approvals on 2026-08-25.
    expect(script, contains("PHASE_DEFERRED = 'deferred'"));
    expect(script, contains('DEFER_MAX_TOTAL'));
    expect(script, contains('def run_failure_kind('));
    // The bot's gh token IS the owner's account, so a bot-applied `approved`
    // would pass ALLOWED_APPROVERS and silently re-date the frozen snapshot.
    // The bot must never add that label — only remove it at pickup.
    expect(script, isNot(contains('add=(LABEL_APPROVED')));
    // roadmate is a PUBLIC repo: runner paths stay out of issue comments.
    expect(script, contains('def redact_paths('));
    // Long-lived subscription token support and push alerts: the bot acts
    // with the owner's own GitHub token, so GitHub never notifies him of
    // its activity — ntfy is the only channel he actually sees.
    expect(script, contains('CLAUDE_CODE_OAUTH_TOKEN'));
    expect(script, contains('import notify'));
    expect(script, contains('work-report.md'));
  });

  test('bot scripts keep their executable bit', () {
    // The cron line and the documented invocations run these directly; a
    // Write without chmod once shipped setup_fix_issues.sh as 100644.
    for (final path in [
      'scripts/fix_issues.py',
      'scripts/setup_fix_issues.sh',
      'scripts/notify.py',
    ]) {
      final mode = File(path).statSync().mode;
      expect(mode & 0x40, isNot(0), reason: '$path must be owner-executable');
    }
  });

  test('setup script provisions labels, hook and git identity', () {
    final setup = File('scripts/setup_fix_issues.sh').readAsStringSync();
    for (final label in [
      'ensure_label approved',
      'claude-working',
      'claude-blocked',
    ]) {
      expect(setup, contains(label));
    }
    expect(setup, contains('commit-msg'));
    expect(setup, contains('Co-Authored-By'));
    expect(setup, contains('user.name'));
    expect(setup, contains('user.email'));
    // A tick that dies before its own alerting can run must still reach the
    // owner: the crontab line carries the notify.py backstop (the live
    // crontab had it; a fresh install used to lose it silently).
    expect(setup, contains('notify.py'));
  });
}
