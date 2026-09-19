// Live-session state machine (Task 12, FR-4.1..FR-4.8; AT-3, AT-11, AT-12, AT-25).
// Pure logic implementing the session lifecycle of design.md §5.2:
//
//   IDLE -> CONNECTING -> PROBING -> LIVE -> BACKGROUNDED(<=5min) -> LIVE
//              | fail x2                        | >5min
//              v                                v
//            ERROR                           CLOSING -> IDLE
//
// A net drop from LIVE enters RECONNECTING; success returns to LIVE with the
// same sticky mode; two failures go to CLOSING. Auth recovery on session expiry
// is a distinct, non-destructive state that preserves the current state and
// resumes it on success (FR-1.5, FR-4.8). This file owns the transition rules so
// they are exhaustively unit-testable without a WebView or a live Ring device.

import 'package:flutter/foundation.dart';

/// Every state of a single live session (design.md §5.2).
enum SessionState {
  /// No session. The starting and terminal state.
  idle,

  /// Establishing the single WebRTC peer connection (ARCH-1, FR-4.1).
  connecting,

  /// Peer connection is up; running the capability probe (design.md §5.1).
  probing,

  /// The session is live: inbound video renders and captions flow (FR-4.2).
  live,

  /// The app is backgrounded; the session is held alive for up to 5 minutes
  /// (FR-4.3a). Resumes to [live] on foreground within the window.
  backgrounded,

  /// A network drop is being recovered; at most 2 attempts (FR-4.4 style),
  /// then close. Privacy Mode keeps captioning locally meanwhile (design §5.2).
  reconnecting,

  /// A non-destructive auth-recovery prompt is showing (FR-1.5, FR-4.8). The
  /// pre-expiry state is preserved and resumed on success.
  authRecovering,

  /// The session is tearing down: peer connection closing, session URL released.
  closing,

  /// Terminal failure: connection setup failed after retries (FR-4.4).
  error,
}

/// The connectivity outcome the WebView/peer connection reports.
enum ConnectionResult { connected, failed }

/// The maximum number of connection setup attempts before ERROR (FR-4.4).
const int kMaxConnectAttempts = 2;

/// The maximum number of reconnect attempts after a live drop before CLOSING
/// (design.md §5.2 "two failures go to CLOSING").
const int kMaxReconnectAttempts = 2;

/// The background survival window (FR-4.3a): 5 minutes.
const Duration kBackgroundSurvivalWindow = Duration(minutes: 5);

/// The sticky caption mode of the session. Mirrors design §3 CaptionMode; a live
/// session never switches mode mid-session (FR-10.1, design §5.4).
enum SessionCaptionMode { clarity, privacy }

/// An immutable snapshot of the session for the UI to render.
@immutable
class SessionSnapshot {
  const SessionSnapshot({
    required this.state,
    required this.mode,
    required this.deviceId,
    required this.connectAttempts,
    required this.reconnectAttempts,
    this.backgroundedAtMs,
    this.stateBeforeAuthRecovery,
    this.errorMessage,
  });

  final SessionState state;
  final SessionCaptionMode mode;
  final String deviceId;
  final int connectAttempts;
  final int reconnectAttempts;

  /// Monotonic timestamp (ms) when the app was backgrounded, null otherwise.
  final int? backgroundedAtMs;

  /// The state to resume after auth recovery succeeds (FR-1.5), null otherwise.
  final SessionState? stateBeforeAuthRecovery;

  /// A dash-free user-facing message for the ERROR state (FR-4.4). NFR-10.
  final String? errorMessage;

  /// The session is showing live video and captions right now.
  bool get isLive => state == SessionState.live;

  /// A session exists (any non-terminal, non-idle state).
  bool get isActive =>
      state != SessionState.idle &&
      state != SessionState.closing &&
      state != SessionState.error;
}
