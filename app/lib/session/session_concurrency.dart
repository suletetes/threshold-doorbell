// Session concurrency rules (Task 12, FR-4.6, FR-4.7; AT-11). Exactly one live
// session exists at a time. When a new event arrives while a session is active:
//
//   - same device  -> update the current session context and replay the haptic,
//                      do NOT open a second session (FR-4.6).
//   - different dev -> queue it as a notification, do NOT interrupt the active
//                      session (FR-4.7).
//
// Pure decision function so the rule is exhaustively unit-testable.

import 'package:flutter/foundation.dart';

/// What the app should do with an incoming event during an active session.
enum ConcurrencyAction {
  /// No session is active: this event may open a session normally.
  openAllowed,

  /// Same device as the active session: update context and replay haptic
  /// (FR-4.6). Never a second session.
  updateContextSameDevice,

  /// Different device: queue as a notification (FR-4.7). Never interrupts.
  queueDifferentDevice,
}

/// The result of applying an incoming event to the concurrency state.
@immutable
class ConcurrencyDecision {
  const ConcurrencyDecision({required this.action, required this.replayHaptic});

  final ConcurrencyAction action;

  /// Whether the alert's haptic should replay (FR-4.6 replays on same device).
  final bool replayHaptic;
}

/// Decide what to do with an event for [eventDeviceId] given the currently
/// active session's [activeDeviceId] (null when no session is active).
ConcurrencyDecision decideConcurrency({
  required String? activeDeviceId,
  required String eventDeviceId,
}) {
  if (activeDeviceId == null) {
    return const ConcurrencyDecision(
      action: ConcurrencyAction.openAllowed,
      replayHaptic: false,
    );
  }
  if (activeDeviceId == eventDeviceId) {
    // Same device: update context, replay haptic, no second session (FR-4.6).
    return const ConcurrencyDecision(
      action: ConcurrencyAction.updateContextSameDevice,
      replayHaptic: true,
    );
  }
  // Different device: queue as a notification, do not interrupt (FR-4.7).
  return const ConcurrencyDecision(
    action: ConcurrencyAction.queueDifferentDevice,
    replayHaptic: false,
  );
}
