import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What the GitHub API answers, keyed by endpoint (relative to the repo).
/// `null` makes that endpoint fail, as a 404 / network error would.
typedef _Api = Map<String, Object?>;

const _repo = 'repos/darumatic/roadmate';

/// Every setting as scripts/github_security.sh wants it.
_Api _asExpected() => {
  '': {
    'security_and_analysis': {
      'secret_scanning': {'status': 'enabled'},
      'secret_scanning_push_protection': {'status': 'enabled'},
      'dependabot_security_updates': {'status': 'enabled'},
    },
  },
  '/vulnerability-alerts': '',
  '/private-vulnerability-reporting': {'enabled': true},
  '/code-scanning/default-setup': {
    'state': 'configured',
    'query_suite': 'extended',
    'languages': [
      'actions',
      'javascript',
      'javascript-typescript',
      'python',
      'typescript',
    ],
  },
  '/actions/permissions/workflow': {
    'default_workflow_permissions': 'read',
    'can_approve_pull_request_reviews': false,
  },
  '/actions/permissions/fork-pr-contributor-approval': {
    'approval_policy': 'all_external_contributors',
  },
  '/rulesets': [
    // A disabled ruleset GitHub created on its own: must not count.
    {'id': 1, 'enforcement': 'disabled', 'target': 'branch'},
    {'id': 2, 'enforcement': 'active', 'target': 'branch'},
  ],
  '/rulesets/2': {
    'conditions': {
      'ref_name': {
        'include': ['~DEFAULT_BRANCH'],
        'exclude': <String>[],
      },
    },
    'rules': [
      {'type': 'deletion'},
      {'type': 'non_fast_forward'},
    ],
  },
};

class _Result {
  _Result(this.exitCode, this.stdout, this.stderr, this.writes);

  final int exitCode;
  final String stdout;
  final String stderr;

  /// One entry per NON-GET `gh api` call: its arguments.
  final List<String> writes;
}

/// Runs the real script against a stub `gh` that serves [api] and records
/// every write. Hermetic environment: the point of the script is what it
/// tells GitHub, so a real `gh` (or token) must never be reachable from here.
_Result _run(_Api api, {List<String> args = const []}) {
  final dir = Directory.systemTemp.createTempSync('github_security_test');
  try {
    String fileFor(String path) =>
        '${dir.path}/${'$_repo$path'.replaceAll('/', '_')}.json';
    api.forEach((path, answer) {
      if (answer == null) return;
      File(
        fileFor(path),
      ).writeAsStringSync(answer is String ? answer : jsonEncode(answer));
    });
    final stub = File('${dir.path}/gh')
      ..writeAsStringSync(r'''#!/usr/bin/env bash
dir="$(dirname "$0")"
[ "$1" = "api" ] || exit 1
shift
if [ "$1" = "-X" ]; then
  printf '%s\n' "$*" >> "$dir/writes.log"
  cat > /dev/null < /dev/stdin || true
  exit 0
fi
f="$dir/$(printf '%s' "$1" | tr '/' '_').json"
if [ -f "$f" ]; then cat "$f"; else echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
''');
    Process.runSync('chmod', ['+x', stub.path]);

    final result = Process.runSync(
      'bash',
      ['scripts/github_security.sh', ...args],
      includeParentEnvironment: false,
      environment: {
        'PATH': '${dir.path}:${Platform.environment['PATH']}',
        'HOME': dir.path,
      },
    );
    final log = File('${dir.path}/writes.log');
    return _Result(
      result.exitCode,
      result.stdout as String,
      result.stderr as String,
      log.existsSync() ? log.readAsLinesSync() : const [],
    );
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void main() {
  // These settings live in GitHub, not in the repo, and nothing re-applies
  // them (no org security configuration is attached). For months the docs
  // said CodeQL was kept on org-side while it had never been configured —
  // the script is the record of the intended state, and these pin what it
  // accepts, what it refuses, and what --apply sends.
  group('scripts/github_security.sh', () {
    final hasJq =
        Process.runSync('bash', ['-c', 'command -v jq']).exitCode == 0;
    final skip = hasJq ? null : 'jq is not installed (the script needs it)';

    test('the expected settings pass, and --check writes nothing', () {
      final r = _run(_asExpected());

      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
      expect(r.stdout, contains('All security settings are as expected.'));
      expect(r.stdout, isNot(contains('DRIFT')));
      expect(r.writes, isEmpty);
    }, skip: skip);

    test('push protection switched off is drift, by name, exit 1', () {
      final api = _asExpected();
      ((api['']! as Map)['security_and_analysis']
          as Map)['secret_scanning_push_protection'] = {
        'status': 'disabled',
      };
      final r = _run(api);

      expect(r.exitCode, 1);
      expect(
        r.stdout,
        contains('DRIFT  secret scanning push protection = disabled'),
      );
      expect(r.stderr, contains('--apply'));
    }, skip: skip);

    test('a permissive default workflow token is drift', () {
      final api = _asExpected();
      api['/actions/permissions/workflow'] = {
        'default_workflow_permissions': 'write',
        'can_approve_pull_request_reviews': true,
      };
      final r = _run(api);

      expect(r.exitCode, 1);
      expect(r.stdout, contains('DRIFT  default workflow token = write'));
      expect(
        r.stdout,
        contains('DRIFT  Actions may approve pull requests = true'),
      );
    }, skip: skip);

    // The one "more is worse" setting: CodeQL must BUILD Kotlin and Swift,
    // cannot build a Flutter project, and a failed scan blocks every release
    // at the pipeline's CodeQL gate.
    test('selecting java-kotlin or swift for CodeQL is drift', () {
      final api = _asExpected();
      ((api['/code-scanning/default-setup']! as Map)['languages'] as List)
        ..add('java-kotlin')
        ..add('swift');
      final r = _run(api);

      expect(r.exitCode, 1);
      expect(r.stdout, contains('DRIFT  CodeQL analyses java-kotlin = yes'));
      expect(r.stdout, contains('DRIFT  CodeQL analyses swift = yes'));
    }, skip: skip);

    test('CodeQL never configured is drift', () {
      final api = _asExpected();
      api['/code-scanning/default-setup'] = {
        'state': 'not-configured',
        'query_suite': 'default',
        'languages': <String>[],
      };
      final r = _run(api);

      expect(r.exitCode, 1);
      expect(
        r.stdout,
        contains('DRIFT  CodeQL default setup = not-configured'),
      );
      expect(r.stdout, contains('DRIFT  CodeQL analyses python = no'));
    }, skip: skip);

    test('a ruleset only counts if it is active AND blocks both force-pushes '
        'and deletion of the default branch', () {
      final api = _asExpected();
      (api['/rulesets/2']! as Map)['rules'] = [
        {'type': 'deletion'},
      ];
      final r = _run(api);

      expect(r.exitCode, 1);
      expect(
        r.stdout,
        contains('DRIFT  master blocks force-push and deletion = no'),
      );
    }, skip: skip);

    test(
      'Dependabot alerts off (the endpoint 404s) is drift, not a crash',
      () {
        final api = _asExpected()..['/vulnerability-alerts'] = null;
        final r = _run(api);

        expect(r.exitCode, 1);
        expect(r.stdout, contains('DRIFT  Dependabot alerts = disabled'));
      },
      skip: skip,
    );

    test('a setting that cannot be READ is "could not run", never "ok"', () {
      final api = _asExpected()..['/actions/permissions/workflow'] = null;
      final r = _run(api);

      expect(r.exitCode, 2);
      expect(r.stderr, contains('could not run'));
      expect(
        r.stdout,
        isNot(contains('All security settings are as expected')),
      );
    }, skip: skip);

    test(
      '--apply sends every setting, and leaves an existing ruleset alone',
      () {
        final r = _run(_asExpected(), args: ['--apply']);

        expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
        final writes = r.writes.join('\n');
        expect(writes, contains('-X PATCH $_repo --input -'));
        expect(writes, contains('-X PUT $_repo/vulnerability-alerts'));
        expect(writes, contains('-X PUT $_repo/automated-security-fixes'));
        expect(
          writes,
          contains('-X PUT $_repo/private-vulnerability-reporting'),
        );
        expect(
          writes,
          contains(
            '-X PUT $_repo/actions/permissions/workflow '
            '-f default_workflow_permissions=read '
            '-F can_approve_pull_request_reviews=false',
          ),
        );
        expect(writes, contains('approval_policy=all_external_contributors'));
        expect(
          writes,
          contains(
            '-X PATCH $_repo/code-scanning/default-setup -f state=configured '
            '-f query_suite=extended -f languages[]=actions '
            '-f languages[]=javascript-typescript -f languages[]=python',
          ),
        );
        // Never the two that cannot be built here.
        expect(writes, isNot(contains('java-kotlin')));
        expect(writes, isNot(contains('swift')));
        expect(writes, isNot(contains('-X POST $_repo/rulesets')));
      },
      skip: skip,
    );

    test('--apply creates the ruleset when none protects master', () {
      final api = _asExpected()..['/rulesets'] = <Object>[];
      final r = _run(api, args: ['--apply']);

      expect(
        r.writes.join('\n'),
        contains('-X POST $_repo/rulesets --input -'),
      );
    }, skip: skip);

    test('an unknown flag is refused rather than treated as --check', () {
      final r = _run(_asExpected(), args: ['--aply']);
      expect(r.exitCode, 2);
      expect(r.writes, isEmpty);
    });
  });

  group('security files in the repo', () {
    test('SECURITY.md sends reporters to private vulnerability reporting '
        'and publishes no personal address', () {
      final policy = File('SECURITY.md').readAsStringSync();

      expect(
        policy,
        contains(
          'https://github.com/darumatic/roadmate/security/advisories/new',
        ),
      );
      expect(policy.toLowerCase(), contains('privately'));
      // A public repo: reports go through the advisory, not someone's inbox.
      expect(RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+').hasMatch(policy), isFalse);
      // The Firebase client keys are flagged by every scanner and are public
      // by design — saying so up front saves a report.
      expect(policy, contains('lib/firebase_options.dart'));
    });

    test('Dependabot keeps the pinned actions moving, and only them', () {
      final config = File('.github/dependabot.yml').readAsStringSync();

      expect(config, contains('package-ecosystem: github-actions'));
      // One grouped PR, not one per action: every merge is a production deploy.
      expect(config, contains('groups:'));
      // pub/gradle/npm version bumps are maintenance, not security; vulnerable
      // dependencies are covered by Dependabot SECURITY updates (a setting).
      expect(
        RegExp(
          r'^\s*- package-ecosystem:',
          multiLine: true,
        ).allMatches(config).length,
        1,
      );
    });
  });
}
