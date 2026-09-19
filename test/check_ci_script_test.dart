import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// One canned GitHub API answer: the JSON body and the HTTP status.
typedef _Answer = (String body, int code);

const _rateLimited = (
  '{"message":"API rate limit exceeded for 203.0.113.7.","documentation_url":"https://docs.github.com"}',
  403,
);
const _noRunYet = ('{"total_count":0,"workflow_runs":[]}', 200);

_Answer _run(String status, [String? conclusion]) => (
  '{"workflow_runs":[{"status":"$status",'
      '"conclusion":${conclusion == null ? 'null' : '"$conclusion"'},'
      '"html_url":"https://github.com/darumatic/roadmate/actions/runs/1"}]}',
  200,
);

class _Result {
  _Result(this.exitCode, this.stdout, this.stderr, this.curlArgs, this.sleeps);

  final int exitCode;
  final String stdout;
  final String stderr;

  /// One entry per request: the arguments `curl` was called with.
  final List<String> curlArgs;

  /// One entry per pause: the seconds `sleep` was asked for.
  final List<String> sleeps;
}

/// Runs the real script against stubbed `curl` / `sleep` / `gh` on PATH.
/// [answers] are served in order; the last one repeats forever. The
/// environment is built from scratch — the suite also runs inside store
/// builds and CI, where a real GH_TOKEN/GITHUB_TOKEN may be exported, and
/// which one is present is exactly what these tests are about.
_Result _runScript(List<_Answer> answers, {String? envToken, String? ghToken}) {
  final dir = Directory.systemTemp.createTempSync('check_ci_test');
  try {
    void stub(String name, String body) {
      final file = File('${dir.path}/$name')
        ..writeAsStringSync('#!/usr/bin/env bash\n$body');
      Process.runSync('chmod', ['+x', file.path]);
    }

    for (var i = 0; i < answers.length; i++) {
      final name = i == answers.length - 1 ? 'last' : '${i + 1}';
      File('${dir.path}/resp.$name.body').writeAsStringSync(answers[i].$1);
      File('${dir.path}/resp.$name.code').writeAsStringSync('${answers[i].$2}');
    }
    // Mimics `curl -s -w '\n%{http_code}'`: the body, then the status line.
    stub('curl', r'''
dir="$(dirname "$0")"
n=$(( $(cat "$dir/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$dir/count"
printf '%s\n' "$*" >> "$dir/curl.args"
f="$dir/resp.$n"
[ -f "$f.body" ] || f="$dir/resp.last"
cat "$f.body"
printf '\n%s' "$(cat "$f.code")"
''');
    stub(
      'sleep',
      r'echo "$1" >> "$(dirname "$0")/sleep.log"'
          '\n',
    );
    stub(
      'gh',
      ghToken == null
          ? 'exit 1\n'
          : '[ "\$1 \$2" = "auth token" ] && echo "$ghToken" || exit 1\n',
    );

    final result = Process.runSync(
      'bash',
      ['scripts/check_ci.sh', 'HEAD'],
      includeParentEnvironment: false,
      environment: {
        'PATH': '${dir.path}:${Platform.environment['PATH']}',
        'HOME': Platform.environment['HOME'] ?? dir.path,
        'GH_TOKEN': ?envToken,
      },
    );

    List<String> lines(String name) {
      final file = File('${dir.path}/$name');
      return file.existsSync()
          ? file.readAsLinesSync().where((l) => l.isNotEmpty).toList()
          : const [];
    }

    return _Result(
      result.exitCode,
      result.stdout as String,
      result.stderr as String,
      lines('curl.args'),
      lines('sleep.log'),
    );
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void main() {
  test('check_ci.sh expands its sha argument to the full 40-char form', () {
    // GitHub's head_sha filter only matches the full sha; a short sha matches
    // no runs, so the script would poll "queued" until timeout. The script
    // must normalise its argument through git rev-parse.
    final script = File('scripts/check_ci.sh').readAsStringSync();
    expect(script, contains(r'sha="$(git rev-parse "${1:-HEAD}")"'));
  });

  group('check_ci.sh against the GitHub API', () {
    final hasJq =
        Process.runSync('bash', ['-c', 'command -v jq']).exitCode == 0;
    final skip = hasJq ? null : 'jq is not installed (the script needs it)';

    // The v1.0.22 release: the pipeline FAILED, yet the poller printed
    // "queued" for the rest of its 40 minutes. Anonymous callers get 60
    // requests an hour; at one per 15 s that is gone in 15 minutes, every
    // later answer is a 403, and the old `// "queued"` fallback read the
    // error body as "no run yet".
    test('a rate-limited answer is reported as an API error — never as '
        '"queued" — and the failed release still ends red', () {
      final r = _runScript([
        _rateLimited,
        _rateLimited,
        _run('completed', 'failure'),
      ]);

      expect(r.exitCode, 1);
      expect(r.stderr, contains('WARNING: GitHub API answered 403'));
      expect(r.stderr, contains('API rate limit exceeded'));
      expect(r.stdout, isNot(contains('queued')));
      expect(r.stderr, contains('Web release failed (failure)'));
      // The auto-fixer reads anything that is not "Timed out" as red.
      expect(r.stderr, isNot(contains('Timed out')));
    }, skip: skip);

    test('a green release exits 0 with the run url', () {
      final r = _runScript([
        _noRunYet,
        _run('in_progress'),
        _run('completed', 'success'),
      ]);

      expect(r.exitCode, 0);
      // No run yet really is "still queued".
      expect(r.stdout, contains('Web Release queued...'));
      expect(r.stdout, contains('Web Release in_progress...'));
      expect(r.stdout, contains('Web release landed: https://github.com/'));
    }, skip: skip);

    test('anonymous, it polls once a minute — all 60 requests/hour allow', () {
      final r = _runScript([_run('in_progress'), _run('completed', 'success')]);

      expect(r.sleeps, ['60']);
      expect(r.curlArgs, hasLength(2));
      expect(r.curlArgs, everyElement(isNot(contains('Authorization'))));
    }, skip: skip);

    test('with a token in the environment it signs the request and keeps '
        'the fast cadence', () {
      final r = _runScript([
        _run('in_progress'),
        _run('completed', 'success'),
      ], envToken: 'env-token');

      expect(r.sleeps, ['15']);
      expect(
        r.curlArgs,
        everyElement(contains('Authorization: Bearer env-token')),
      );
    }, skip: skip);

    test("with no token in the environment it borrows gh's", () {
      final r = _runScript([
        _run('in_progress'),
        _run('completed', 'success'),
      ], ghToken: 'gh-token');

      expect(r.sleeps, ['15']);
      expect(
        r.curlArgs,
        everyElement(contains('Authorization: Bearer gh-token')),
      );
    }, skip: skip);

    test('a refused token falls back to anonymous polling instead of '
        'failing every request', () {
      final r = _runScript([
        ('{"message":"Bad credentials"}', 401),
        _run('completed', 'success'),
      ], envToken: 'expired');

      expect(r.exitCode, 0);
      expect(r.stderr, contains('GitHub API answered 401: Bad credentials'));
      expect(r.stderr, contains('continuing unauthenticated'));
      expect(r.curlArgs.first, contains('Authorization: Bearer expired'));
      expect(r.curlArgs.last, isNot(contains('Authorization')));
      expect(r.sleeps, ['60']);
    }, skip: skip);

    test('a run that never finishes ends with the "Timed out" message the '
        'auto-fixer classifies on, after ~40 minutes of polls', () {
      final r = _runScript([_run('in_progress')]);

      expect(r.exitCode, 1);
      expect(
        r.stderr,
        contains('Timed out waiting for the Web Release run on'),
      );
      // 40 one-minute polls: the same ceiling the fast cadence reaches in 160.
      expect(r.sleeps, List.filled(40, '60'));
    }, skip: skip);
  });
}
