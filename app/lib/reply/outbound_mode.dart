// Sticky outbound-mode state machine (Task 16, FR-6.4, FR-6.4a, FR-6.4b; AT-6).
// The capability probe (design.md §5.1) runs once per session; its result is
// sticky for the whole session. If a later injection attempt fails, the session
// degrades to Captions-Only for the remainder and does NOT auto-recover. The
// next session re-probes from scratch. The actual WebRTC probe and injection are
// device/Ring-bound; this pure state machine is driven by fixture probe/injection
// results so the sticky-mode rules are exhaustively unit-testable.

import 'package:flutter/foundation.dart';

/// The lifecycle states of outbound capability within a single session.
enum OutboundState {
  /// Before the probe has run (peer connection not yet probed).
  unprobed,

  /// Probe succeeded: two-way replies available for this session.
  twoWay,

  /// Probe failed at start: Captions-Only for the whole session (FR-6.4a).
  captionsOnlyFromProbe,

  /// Probe succeeded but a later injection failed: degraded to Captions-Only for
  /// the remainder, no auto-recovery this session (FR-6.4b).
  captionsOnlyDegraded,
}

/// Result of the near-silent capability probe (design.md §5.1).
enum ProbeResult { success, failure }

@immutable
class OutboundModeSnapshot {
  const OutboundModeSnapshot(this.state);
  final OutboundState state;

  /// Whether spoken replies are available right now.
  bool get outboundAvailable => state == OutboundState.twoWay;

  /// Whether the UI should show the Captions-Only banner (FR-12.2).
  bool get isCaptionsOnly =>
      state == OutboundState.captionsOnlyFromProbe ||
      state == OutboundState.captionsOnlyDegraded;
}

/// A single session's outbound-mode state machine. One instance per session; a
/// new session must use a new instance so it re-probes from scratch (FR-6.4b).
class OutboundModeMachine {
  OutboundState _state = OutboundState.unprobed;
  bool _probed = false;

  OutboundState get state => _state;
  OutboundModeSnapshot get snapshot => OutboundModeSnapshot(_state);
  bool get outboundAvailable => _state == OutboundState.twoWay;
  bool get isCaptionsOnly => snapshot.isCaptionsOnly;

  /// Apply the probe result at session start. The probe runs exactly once; a
  /// second probe call is ignored so the result stays sticky (FR-6.4b).
  void applyProbe(ProbeResult result) {
    if (_probed) return; // sticky: ignore any re-probe within the session
    _probed = true;
    _state = result == ProbeResult.success
        ? OutboundState.twoWay
        : OutboundState.captionsOnlyFromProbe;
  }

  /// Record the outcome of an injection attempt. A failure while two-way degrades
  /// the session to Captions-Only for the remainder and never auto-recovers
  /// (FR-6.4b). A failure while already Captions-Only is a no-op. An injection
  /// while unprobed is rejected (the probe gates the reply bar per design §5.1).
  void recordInjection({required bool success}) {
    if (!_probed) {
      throw StateError('Injection attempted before the capability probe ran');
    }
    if (_state == OutboundState.twoWay && !success) {
      _state = OutboundState.captionsOnlyDegraded;
    }
    // On success in twoWay: stays twoWay. On any state that is already
    // Captions-Only: no change (no auto-recovery, FR-6.4b).
  }

  /// True once the probe has run (the reply bar is only enabled after this).
  bool get hasProbed => _probed;
}
