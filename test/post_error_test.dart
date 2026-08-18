import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/ban_logic.dart';
import 'package:roadmate/services/post_error.dart';
import 'package:roadmate/services/rate_limit.dart';
import 'package:roadmate/services/report_proximity.dart';

/// The one error→snack-text mapping every posting surface shares. Each branch
/// is policy a hand-copied catch chain used to get subtly wrong.
void main() {
  test('proximity refusals surface their own explanations', () {
    expect(postErrorMessage(const TooFarException()), kTooFarToReportMessage);
    expect(
      postErrorMessage(const LocationRequiredException()),
      kLocationRequiredMessage,
    );
  });

  test('a ban explains itself, permanent or timed', () {
    expect(
      postErrorMessage(const BannedException(null)),
      banNoticeMessage(null),
    );
    final until = DateTime(2026, 9, 1);
    expect(postErrorMessage(BannedException(until)), banNoticeMessage(until));
  });

  test('rate limiting uses the shared cooldown message', () {
    expect(postErrorMessage(const RateLimitedException()), kRateLimitMessage);
  });

  test('anything else falls back to the generic message', () {
    expect(postErrorMessage(StateError('boom')), kPostFailedMessage);
    expect(postErrorMessage(Exception('network')), kPostFailedMessage);
  });
}
