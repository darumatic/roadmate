import 'package:flutter/material.dart';

/// The app's one snack shape. Replaces any showing snack — an explanation
/// must never sit in a queue behind the previous "thanks!" message — and
/// stays brief. Every surface uses this (or [showSnackOn]); there used to be
/// four private `_snack` helpers with quietly different durations and
/// queueing behaviour.
void showAppSnack(BuildContext context, String message) =>
    showSnackOn(ScaffoldMessenger.of(context), message);

/// [showAppSnack] for callers that captured the messenger *before* an await,
/// because their widget is torn down before the result arrives (the
/// proximity prompt card dismisses itself as the vote posts).
void showSnackOn(ScaffoldMessengerState? messenger, String message) {
  messenger
    ?..removeCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
}
