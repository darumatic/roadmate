import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/enums.dart';

/// System notification for the site-approach prompt, used when the app is not
/// on screen. Injectable (mirrors `AlertPlayer`/`LocationSource`) so tests
/// substitute a recorder and never touch the plugin.

/// A single notification slot: a newer approach replaces the previous one
/// rather than stacking a queue the driver has to clear.
const int proximityNotificationId = 7301;

const String proximityChannelId = 'site_approach';
const String proximityChannelName = 'Site alerts';
const String proximityChannelDescription =
    'Asks for the status of an inspection site as you approach it.';

/// Action ids on the notification, mapped back to the vote they cast. Kept as
/// data (rather than a switch inside the plugin callback) so the mapping is
/// unit-testable and the two directions can't drift apart.
const Map<String, SiteStatus> proximityActionStatuses = {
  'vote_open': SiteStatus.open,
  'vote_blitz': SiteStatus.blitz,
  'vote_closed': SiteStatus.closed,
};

/// The vote an action id stands for; null for a plain tap on the notification
/// body (which just opens the app on the prompt).
SiteStatus? statusFromActionId(String? actionId) =>
    actionId == null ? null : proximityActionStatuses[actionId];

/// Notification title, e.g. `Marulan · 2.4 km ahead`. Pure — unit-tested.
String proximityNotificationTitle(String siteName, double km) {
  final distance = km < 1
      ? '${(km * 1000).round()} m ahead'
      : '${km.toStringAsFixed(1)} km ahead';
  return '$siteName · $distance';
}

/// An answer arriving from a notification the user acted on.
class ProximityAnswer {
  const ProximityAnswer({required this.siteId, this.status});

  final String siteId;

  /// null when the user tapped the notification body rather than a vote
  /// action — open the in-app prompt instead of writing anything.
  final SiteStatus? status;
}

abstract class ProximityNotifier {
  /// Prepares the platform channel and registers [onAnswer], which fires when
  /// the user taps the notification or one of its vote actions.
  Future<void> initialise(void Function(ProximityAnswer) onAnswer);

  /// Raises (or replaces) the approach notification.
  Future<void> showApproach({
    required String siteId,
    required String siteName,
    required double km,
    required String body,
  });

  /// Clears it — the driver answered in-app, or the prompt timed out.
  Future<void> cancel();
}

/// Production notifier. Every call is best-effort: a driver must never lose
/// the in-app prompt because a notification channel misbehaved.
class LocalProximityNotifier implements ProximityNotifier {
  LocalProximityNotifier();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Re-bound on every [initialise] call, and read (rather than captured) by
  /// the plugin callback: if the controller is ever rebuilt, answers must
  /// reach the live one, not the instance that happened to init the plugin.
  void Function(ProximityAnswer)? _onAnswer;

  /// Notifications are a native-only affair here: on web the tab has to be
  /// open for the GPS stream to run at all, so the in-app card already covers
  /// every case.
  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<void> initialise(void Function(ProximityAnswer) onAnswer) async {
    _onAnswer = onAnswer;
    if (_ready || !_supported) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: true,
            requestSoundPermission: true,
            requestBadgePermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final siteId = response.payload;
          if (siteId == null || siteId.isEmpty) return;
          _onAnswer?.call(
            ProximityAnswer(
              siteId: siteId,
              status: statusFromActionId(response.actionId),
            ),
          );
        },
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      // Plugin unavailable (or a test harness): stay silent, keep the in-app
      // prompt working.
      debugPrint('RoadMate: notification init failed: $e');
    }
  }

  @override
  Future<void> showApproach({
    required String siteId,
    required String siteName,
    required double km,
    required String body,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: proximityNotificationId,
        title: proximityNotificationTitle(siteName, km),
        body: body,
        payload: siteId,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            proximityChannelId,
            proximityChannelName,
            channelDescription: proximityChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.navigation,
            // Answering must bring the app forward: the vote goes through the
            // normal signed-in Firestore path in the UI isolate, never a
            // background isolate with no Firebase.
            actions: [
              for (final entry in proximityActionStatuses.entries)
                AndroidNotificationAction(
                  entry.key,
                  _actionLabel(entry.value),
                  showsUserInterface: true,
                ),
            ],
          ),
          iOS: const DarwinNotificationDetails(
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
      );
    } catch (e) {
      debugPrint('RoadMate: could not show approach notification: $e');
    }
  }

  @override
  Future<void> cancel() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: proximityNotificationId);
    } catch (e) {
      debugPrint('RoadMate: could not clear approach notification: $e');
    }
  }

  static String _actionLabel(SiteStatus status) => switch (status) {
    SiteStatus.open => 'Open',
    SiteStatus.blitz => 'Blitz',
    SiteStatus.closed => 'Closed',
    SiteStatus.unknown => 'Unknown',
  };
}
