// Caption announcement throttling (LOW-09, FR-5.5; G4). Marking the whole
// caption container as a live region makes a screen reader re-read the entire
// caption run on every partial update, which is noisy and lags behind live
// speech. Instead the app announces each NEWLY FINALIZED turn once, via
// SemanticsService.announce, throttled so a burst of finalized turns does not
// flood the screen reader.
//
// This file owns the pure decision of WHAT to announce and WHEN, so the dedup
// and throttle are unit-testable without a screen reader. The actual
// SemanticsService.announce call is made by the widget that drives this.

import 'package:flutter/foundation.dart';

import 'turn_segmentation.dart';

/// Monotonic clock in milliseconds, injectable for deterministic tests.
typedef NowMs = int Function();

/// Decides which finalized caption turns to announce to a screen reader, once
/// each and no more often than [minGapMs] apart (LOW-09).
class CaptionAnnouncer {
  CaptionAnnouncer({NowMs? nowMs, this.minGapMs = 500})
      : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final NowMs _nowMs;

  /// The minimum gap between announcements, in milliseconds. A burst of
  /// finalized turns within this window announces only the most recent.
  final int minGapMs;

  int _announcedCount = 0; // how many finalized turns have been announced
  int _lastAnnouncedAtMs = -1 << 30;

  /// Given the current ordered [turns], return the announcement string for the
  /// newest finalized turn that has not been announced yet, or null when there
  /// is nothing new to announce or the throttle window has not elapsed.
  ///
  /// Only finalized turns are announced (a provisional turn is still changing).
  /// When several turns finalized since the last call, the newest is announced
  /// and the rest are marked as seen, so the screen reader is not flooded.
  String? announcementFor(List<CaptionTurn> turns) {
    final finalized = turns.where((t) => t.isFinal).toList();
    if (finalized.length <= _announcedCount) {
      // No new finalized turns (or turns were reset for a new session).
      if (finalized.length < _announcedCount) _announcedCount = finalized.length;
      return null;
    }
    final now = _nowMs();
    if (now - _lastAnnouncedAtMs < minGapMs) {
      // Within the throttle window: do not announce yet, and do not consume the
      // new turns so a later call can announce the latest once the window opens.
      return null;
    }
    final latest = finalized.last;
    _announcedCount = finalized.length; // mark all current finalized as seen
    _lastAnnouncedAtMs = now;
    return _spoken(latest);
  }

  /// Reset for a new session (the turn list restarts from empty).
  void reset() {
    _announcedCount = 0;
    _lastAnnouncedAtMs = -1 << 30;
  }

  /// The spoken form of a finalized turn: who said it, then the text.
  String _spoken(CaptionTurn turn) {
    final who = turn.speaker == CaptionSpeaker.visitor ? 'Visitor' : 'You';
    return '$who said: ${turn.text}';
  }
}

/// A debug-visible description of a turn for logging (keeps the announcer file
/// self-contained for tests).
@visibleForTesting
String describeTurn(CaptionTurn turn) =>
    '${turn.speaker.name}:${turn.text}:${turn.isFinal}';
