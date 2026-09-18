// Haptic vocabulary (Task 11, FR-9.1, FR-9.2). Exactly three distinguishable
// vibration patterns in v1: person-at-door, motion, conversation-started. These
// are pure definitions (waveforms as millisecond wait/vibrate pairs) so a deaf
// or hard-of-hearing resident can tell events apart by feel alone, and so they
// are unit-testable without a device. The actual `vibration` platform call is a
// thin adapter (see HapticPlayer); the definitions live here.

import 'package:flutter/foundation.dart';

/// The three event kinds that map to the three haptic patterns (FR-9.1).
enum HapticEvent { personAtDoor, motion, conversationStarted }

/// A vibration pattern expressed as a `vibration`-style timing list: the first
/// entry is an initial wait, then alternating vibrate/pause durations in ms.
/// This is exactly the shape the `vibration` package's `pattern:` argument takes.
@immutable
class HapticPattern {
  const HapticPattern({
    required this.event,
    required this.label,
    required this.timings,
  });

  final HapticEvent event;

  /// Plain-language reference label shown in Settings (FR-9.2). No dashes (NFR-10).
  final String label;

  /// Wait/vibrate/pause timings in milliseconds. Even count, starts with a wait.
  final List<int> timings;

  /// Total duration of the pattern in milliseconds.
  int get totalDurationMs => timings.fold(0, (sum, t) => sum + t);
}

/// The three v1 patterns. Each has a distinct rhythm so it is distinguishable by
/// feel: a long double buzz for a person, three short taps for motion, and a
/// heartbeat-style pair for a started conversation.
class HapticVocabulary {
  HapticVocabulary._();

  static const HapticPattern personAtDoor = HapticPattern(
    event: HapticEvent.personAtDoor,
    label: 'Person at the door',
    // Two long, assertive buzzes.
    timings: <int>[0, 600, 200, 600],
  );

  static const HapticPattern motion = HapticPattern(
    event: HapticEvent.motion,
    label: 'Motion detected',
    // Three short taps.
    timings: <int>[0, 150, 120, 150, 120, 150],
  );

  static const HapticPattern conversationStarted = HapticPattern(
    event: HapticEvent.conversationStarted,
    label: 'Conversation started',
    // A heartbeat: short then long.
    timings: <int>[0, 200, 100, 500],
  );

  /// Exactly three patterns in v1 (FR-9.1). The order is stable for the Settings
  /// reference list.
  static const List<HapticPattern> all = <HapticPattern>[
    personAtDoor,
    motion,
    conversationStarted,
  ];

  /// Look up the pattern for an event. Total function over the enum, so there is
  /// no unhandled case.
  static HapticPattern forEvent(HapticEvent event) {
    switch (event) {
      case HapticEvent.personAtDoor:
        return personAtDoor;
      case HapticEvent.motion:
        return motion;
      case HapticEvent.conversationStarted:
        return conversationStarted;
    }
  }

  /// Map a backend event type string to a haptic event. Returns null for an
  /// unknown type so the caller can decide (no crash on contract drift).
  static HapticEvent? fromEventType(String eventType) {
    switch (eventType) {
      case 'person_detected':
        return HapticEvent.personAtDoor;
      case 'motion_detected':
        return HapticEvent.motion;
      case 'conversation_started':
        return HapticEvent.conversationStarted;
      default:
        return null;
    }
  }
}
