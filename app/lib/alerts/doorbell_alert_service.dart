// Doorbell alert service (FR-3.3, FR-9.1): what the resident FEELS and SEES when
// the doorbell is pressed, because they cannot hear it.
//
// Two jobs:
//   1. Vibrate with the "person at the door" pattern, repeated, until the ring
//      is answered or missed. A deaf resident cannot hear a chime, so the phone
//      must buzz like an incoming call.
//   2. Post a high-priority, call-style notification with a full-screen intent,
//      so a locked or backgrounded phone lights up and shows the ring. A real
//      Android notification also triggers the system Flash notifications
//      accessibility feature (camera light / screen flash) when the resident has
//      turned it on, and buzzes a paired watch.
//
// It also offers a persistent "Listening for your doorbell" notification. On
// Android an ongoing notification keeps the process warmer so the hub WebSocket
// is less likely to be frozen while the app is backgrounded; the resident taps
// it to bring Threshold forward.
//
// All platform calls are best effort and guarded: if a plugin is unavailable
// (for example under `flutter test`), every method is a safe no-op rather than
// throwing. The haptic and strobe SETTINGS are honoured by the caller, which
// passes whether vibration is enabled for the person-at-door event.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

import 'haptic_vocabulary.dart';

/// Notification channel + ids. Stable strings; Android keeps channel settings
/// keyed by id.
const String _kRingChannelId = 'threshold_doorbell_ring';
const String _kRingChannelName = 'Doorbell alerts';
const String _kRingChannelDesc =
    'Alerts you when someone is at your door, with vibration and a full screen alert.';
const int _kRingNotificationId = 7001;

const String _kListeningChannelId = 'threshold_listening';
const String _kListeningChannelName = 'Listening for your doorbell';
const String _kListeningChannelDesc =
    'Keeps Threshold ready to alert you so a doorbell press is not missed.';
const int _kListeningNotificationId = 7002;

/// The doorbell alert service. One instance is created in the composition root
/// (demo build) and reused. In tests it is not constructed, or [available] is
/// false, so nothing touches a platform channel.
class DoorbellAlertService {
  DoorbellAlertService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// Shared instance for the demo build. The debug overlay starts the ring
  /// alert when the visitor rings; the home screen stops it when the resident
  /// answers, declines, or the ring is missed. A single instance means the
  /// vibration loop and the notification are started and stopped on the same
  /// object.
  static final DoorbellAlertService shared = DoorbellAlertService();

  /// Whether the resident has the person-at-door haptic enabled (FR-9.2). The
  /// settings controller keeps this in sync; the alert service reads it when a
  /// ring starts so a disabled haptic is respected without threading the whole
  /// settings object through the demo overlay.
  static bool personAtDoorHapticEnabled = true;

  final FlutterLocalNotificationsPlugin _plugin;

  bool _initialized = false;
  bool _ringing = false;
  Timer? _vibrationLoop;

  /// Initialize the plugin and create the channels. Safe to call more than once.
  /// Returns false if initialization failed (for example no platform binding),
  /// so the caller can fall back to the in-app only path.
  Future<bool> init() async {
    if (_initialized) return true;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);
      await _plugin.initialize(settings);

      final android13 = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (android13 != null) {
        await android13.createNotificationChannel(
          const AndroidNotificationChannel(
            _kRingChannelId,
            _kRingChannelName,
            description: _kRingChannelDesc,
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );
        await android13.createNotificationChannel(
          const AndroidNotificationChannel(
            _kListeningChannelId,
            _kListeningChannelName,
            description: _kListeningChannelDesc,
            importance: Importance.low,
          ),
        );
      }
      _initialized = true;
      return true;
    } catch (e) {
      debugPrint('[THRESHOLD] DoorbellAlertService init failed: $e');
      return false;
    }
  }

  /// Ask for notification permission (Android 13+). Best effort; returns whether
  /// permission is granted (true when the platform does not require a prompt).
  Future<bool> requestPermission() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return true;
      final granted = await android.requestNotificationsPermission();
      return granted ?? true;
    } catch (_) {
      return false;
    }
  }

  /// Whether notifications are currently enabled for the app.
  Future<bool> notificationsEnabled() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return false;
      return (await android.areNotificationsEnabled()) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Post the persistent "listening" notification so a ring can reach a
  /// backgrounded phone. Best effort.
  Future<void> startListening() async {
    if (!await init()) return;
    try {
      await _plugin.show(
        _kListeningNotificationId,
        'Listening for your doorbell',
        'Threshold will alert you when someone is at your door.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _kListeningChannelId,
            _kListeningChannelName,
            channelDescription: _kListeningChannelDesc,
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            showWhen: false,
            category: AndroidNotificationCategory.service,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[THRESHOLD] startListening failed: $e');
    }
  }

  Future<void> stopListening() async {
    try {
      await _plugin.cancel(_kListeningNotificationId);
    } catch (_) {}
  }

  /// Begin the incoming-doorbell alert: a looping vibration plus a call-style
  /// full-screen notification. [vibrationEnabled] reflects the resident's
  /// per-event haptic setting for "person at the door" (FR-9.2). Idempotent.
  Future<void> startRing({required bool vibrationEnabled}) async {
    if (_ringing) return;
    _ringing = true;
    await init();
    if (vibrationEnabled) {
      await _startVibrationLoop();
    }
    await _showRingNotification();
  }

  /// Stop every part of the alert (answered, declined, or missed). Idempotent.
  Future<void> stopRing() async {
    _ringing = false;
    _vibrationLoop?.cancel();
    _vibrationLoop = null;
    try {
      await Vibration.cancel();
    } catch (_) {}
    try {
      await _plugin.cancel(_kRingNotificationId);
    } catch (_) {}
  }

  Future<void> _startVibrationLoop() async {
    final pattern = HapticVocabulary.personAtDoor.timings;
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (!hasVibrator) return;
      // Play the pattern immediately, then repeat it on a timer until the ring
      // ends, so it feels like a persistent incoming call rather than one buzz.
      await Vibration.vibrate(pattern: pattern);
      final cycleMs = HapticVocabulary.personAtDoor.totalDurationMs + 700;
      _vibrationLoop = Timer.periodic(Duration(milliseconds: cycleMs), (_) async {
        if (!_ringing) return;
        try {
          await Vibration.vibrate(pattern: pattern);
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('[THRESHOLD] vibration loop failed: $e');
    }
  }

  Future<void> _showRingNotification() async {
    try {
      // Request a full-screen, call-style intent. On Android 14+ the system
      // grants this only to calling/alarm apps and otherwise shows it as a
      // normal high-priority heads-up notification, so this is safe to request
      // unconditionally: a sideloaded build keeps it, others downgrade cleanly.
      await _plugin.show(
        _kRingNotificationId,
        'Someone is at your door',
        'Open Threshold to see your visitor and reply.',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _kRingChannelId,
            _kRingChannelName,
            channelDescription: _kRingChannelDesc,
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.call,
            fullScreenIntent: true,
            ongoing: true,
            autoCancel: false,
            visibility: NotificationVisibility.public,
            // Let the notification carry the same vibration rhythm so a phone
            // whose app process is frozen still buzzes from the system side.
            vibrationPattern: Int64List.fromList(
              HapticVocabulary.personAtDoor.timings
                  .map((e) => e.toInt())
                  .toList(),
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('[THRESHOLD] ring notification failed: $e');
    }
  }

  Future<void> dispose() async {
    await stopRing();
    await stopListening();
  }
}
