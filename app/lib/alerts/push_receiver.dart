// Push receiving abstraction (Task 11, FR-3.3, FR-3.4, FR-3.5). The live FCM
// binding is device-bound and deferred to the developer's machine; here we model
// the platform-independent contract and a fixture so the alert-dispatch logic
// (which haptic to play, which thumbnail to show, poll fallback) is fully
// unit-testable. See PushAlert for the payload shape carried by FR-3.3.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'haptic_vocabulary.dart';

/// A normalized push payload (FR-3.3: type, timestamp, deviceId, thumbnailUrl).
@immutable
class PushAlert {
  const PushAlert({
    required this.type,
    required this.timestamp,
    required this.deviceId,
    required this.thumbnailUrl,
  });

  final String type; // 'person_detected' | 'motion_detected' | ...
  final String timestamp;
  final String deviceId;
  final String? thumbnailUrl;

  factory PushAlert.fromMap(Map<String, dynamic> data) {
    // Guard each field with `is String` rather than an `as String?` cast: a
    // non-string value in a drifting payload must not throw a TypeError, which
    // would contradict the "no crash on contract drift" claim (LOW-01).
    String str(Object? value) => value is String ? value : '';
    final thumb = data['thumbnailUrl'];
    return PushAlert(
      type: str(data['type']),
      timestamp: str(data['timestamp']),
      deviceId: str(data['deviceId']),
      thumbnailUrl: thumb is String ? thumb : null,
    );
  }
}

/// What the app should do when an alert arrives (FR-3.4): which haptic to play
/// and which thumbnail to show full-bleed. A null haptic means an unknown event
/// type (contract drift) that the UI can show generically without crashing.
@immutable
class AlertDispatch {
  const AlertDispatch({required this.haptic, required this.thumbnailUrl});

  final HapticEvent? haptic;
  final String? thumbnailUrl;

  bool get isKnownEvent => haptic != null;
}

/// Pure mapping from a received push to the dispatch decision. Testable without
/// any device: given a payload, decide the haptic and thumbnail (FR-3.4).
AlertDispatch dispatchForAlert(PushAlert alert) {
  return AlertDispatch(
    haptic: HapticVocabulary.fromEventType(alert.type),
    thumbnailUrl: alert.thumbnailUrl,
  );
}

/// Source of pushes. The real implementation binds firebase_messaging (deferred
/// to device). The fixture lets tests deliver alerts deterministically and model
/// the FR-3.5 poll fallback when push is unavailable.
abstract class PushReceiver {
  /// Whether live push delivery is available (notifications granted + FCM up).
  bool get isPushAvailable;

  /// Stream of incoming alerts. On real FCM this is the message stream; the
  /// fixture emits from [deliver].
  Stream<PushAlert> get alerts;
}

/// Deterministic fixture push receiver for tests and local/demo runs.
class FixturePushReceiver implements PushReceiver {
  FixturePushReceiver({bool pushAvailable = true}) : _available = pushAvailable;

  bool _available;
  final List<PushAlert> _delivered = <PushAlert>[];

  // A broadcast controller so a subscriber attached before delivery actually
  // receives the alert. The old Stream.fromIterable snapshot only replayed what
  // had already been delivered, so a live subscriber missed later events
  // (LOW-02).
  final StreamController<PushAlert> _controller =
      StreamController<PushAlert>.broadcast();

  @override
  bool get isPushAvailable => _available;

  set pushAvailable(bool value) => _available = value;

  /// All alerts delivered so far (assertion helper for tests).
  List<PushAlert> get delivered => List.unmodifiable(_delivered);

  /// Deliver an alert. When push is unavailable this returns false so the caller
  /// falls back to the foreground poll (FR-3.5); it does not silently drop.
  bool deliver(PushAlert alert) {
    if (!_available) return false;
    _delivered.add(alert);
    _controller.add(alert);
    return true;
  }

  @override
  Stream<PushAlert> get alerts => _controller.stream;

  /// Release the controller (test teardown).
  Future<void> dispose() => _controller.close();
}
