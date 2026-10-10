// Sticky outbound-mode state machine. A capability probe runs once per session;
// its result is sticky for the whole session. If a later injection attempt
// fails, the session degrades to captions-only for the remainder and does NOT
// auto-recover. The next session re-probes from scratch. Extracted from the
// Threshold project; the actual WebRTC probe and injection are host-app bound.

import 'package:flutter/foundation.dart';

/// The lifecycle states of outbound capability within a single session.
enum OutboundState {
  unprobed,
  twoWay,
  captionsOnlyFromProbe,
  captionsOnlyDegraded,
}

/// Result of the near-silent capability probe.
enum ProbeResult { success, failure }

@immutable
class OutboundModeSnapshot {
  const OutboundModeSnapshot(this.state);
  final OutboundState state;

  bool get outboundAvailable => state == OutboundState.twoWay;
  bool get isCaptionsOnly =>
      state == OutboundState.captionsOnlyFromProbe ||
      state == OutboundState.captionsOnlyDegraded;
}

/// A single session's outbound-mode state machine. One instance per session so a
/// new session re-probes from scratch.
class OutboundModeMachine {
  OutboundState _state = OutboundState.unprobed;
  bool _probed = false;

  OutboundState get state => _state;
  OutboundModeSnapshot get snapshot => OutboundModeSnapshot(_state);
  bool get outboundAvailable => _state == OutboundState.twoWay;
  bool get isCaptionsOnly => snapshot.isCaptionsOnly;
  bool get hasProbed => _probed;

  /// Apply the probe result at session start. The probe runs exactly once; a
  /// second probe call is ignored so the result stays sticky.
  void applyProbe(ProbeResult result) {
    if (_probed) return;
    _probed = true;
    _state = result == ProbeResult.success
        ? OutboundState.twoWay
        : OutboundState.captionsOnlyFromProbe;
  }

  /// Record the outcome of an injection attempt. A failure while two-way degrades
  /// the session to captions-only for the remainder and never auto-recovers.
  ///
  /// Calling this before the probe has run is a programming error and throws.
  /// Calling it once the session is already captions-only (either from the probe
  /// or from an earlier degrade) is a deliberate NO-OP, not an error (LOW-23):
  /// the reply bar is disabled in captions-only mode so a host app should not be
  /// injecting, but the state is terminal for the session and there is nothing
  /// left to downgrade. The no-op keeps a late or racing injection callback from
  /// throwing and crashing the session. Use [isCaptionsOnly] to gate the UI.
  void recordInjection({required bool success}) {
    if (!_probed) {
      throw StateError('Injection attempted before the capability probe ran');
    }
    if (_state == OutboundState.twoWay && !success) {
      _state = OutboundState.captionsOnlyDegraded;
    }
    // In any captions-only state this is a documented no-op: no auto-recovery
    // and no further downgrade are possible.
  }
}
