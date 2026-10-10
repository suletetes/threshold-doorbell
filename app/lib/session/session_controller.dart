// Live-session controller (Task 12, FR-4.1..FR-4.8; AT-3, AT-11, AT-12, AT-25).
//
// Ties together the pure lifecycle (session_state.dart), the device binding
// (SessionPort behind a fake), the capability probe wired into the sticky
// OutboundModeMachine, the concurrency rule (one live session), the 5-minute
// background survival window with resume, and the unified auth-recovery flow.
//
// It is a ChangeNotifier so a Riverpod provider rebuilds the Conversation screen
// on every transition. The 5-minute window uses an injectable clock so AT-25 is
// deterministic under `flutter test` (no wall-clock waits).

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../captions/turn_segmentation.dart';
import '../reply/outbound_mode.dart';
import 'session_concurrency.dart';
import 'session_port.dart';
import 'session_state.dart';

/// Monotonic clock in milliseconds, injectable for deterministic tests.
typedef NowMs = int Function();

/// A single queued notification for a different device (FR-4.7).
@immutable
class QueuedEvent {
  const QueuedEvent({required this.deviceId, required this.eventType});
  final String deviceId;
  final String eventType;
}

class SessionController extends ChangeNotifier {
  SessionController({
    required SessionPort port,
    NowMs? nowMs,
  })  : _port = port,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch) {
    _sub = _port.events.listen(_onPortEvent);
  }

  final SessionPort _port;
  final NowMs _nowMs;
  late final StreamSubscription<SessionPortEvent> _sub;

  /// Monotonically increasing token for each open() call. end() bumps it so an
  /// in-flight open() that is still awaiting connect/probe sees a stale token
  /// and abandons its result instead of resurrecting a session the user ended
  /// (HIGH-04).
  int _openGeneration = 0;

  // --- Session state ---
  SessionState _state = SessionState.idle;
  SessionCaptionMode _mode = SessionCaptionMode.clarity;
  String _deviceId = '';
  int _connectAttempts = 0;
  int _reconnectAttempts = 0;
  int? _backgroundedAtMs;
  SessionState? _stateBeforeAuthRecovery;
  String? _errorMessage;
  NegotiatedMedia? _media;

  /// The sticky outbound-mode machine for THIS session. A new session must use a
  /// new machine so it re-probes from scratch (FR-6.4b); we replace it on start.
  OutboundModeMachine _outbound = OutboundModeMachine();

  /// Accumulates live caption results into labeled turns (FR-5.5, FR-5.7). The
  /// caption surface renders these; a new session starts a fresh accumulator.
  TurnAccumulator _captions = TurnAccumulator();

  /// Events queued for other devices while this session is active (FR-4.7).
  final List<QueuedEvent> _queued = <QueuedEvent>[];

  /// How many times the same-device haptic replayed (FR-4.6). Assertion helper.
  int _sameDeviceHapticReplays = 0;

  // --- Public read surface ---
  SessionState get state => _state;
  SessionCaptionMode get mode => _mode;
  String get deviceId => _deviceId;
  OutboundModeMachine get outbound => _outbound;
  NegotiatedMedia? get negotiatedMedia => _media;
  List<QueuedEvent> get queuedEvents => List.unmodifiable(_queued);
  int get sameDeviceHapticReplays => _sameDeviceHapticReplays;
  int get connectAttempts => _connectAttempts;
  int get reconnectAttempts => _reconnectAttempts;

  /// The active device id while a session exists, else null (FR-4.6/4.7).
  String? get activeDeviceId => _isSessionActive() ? _deviceId : null;

  /// The live caption turns to render on the caption surface (FR-5.5). Rebuilt
  /// as results arrive via [ingestCaption].
  List<CaptionTurn> get captionTurns => _captions.turns;

  /// Ingest a caption result from the ASR/on-device pipeline (Clarity via
  /// /asr/stream, Privacy via the on-device engine). Extends or starts a turn
  /// per the tested segmentation rules and notifies listeners so the caption
  /// surface repaints (FR-5.5, FR-5.7; AT-4).
  void ingestCaption(CaptionResult result) {
    _captions.apply(result);
    notifyListeners();
  }

  SessionSnapshot get snapshot => SessionSnapshot(
        state: _state,
        mode: _mode,
        deviceId: _deviceId,
        connectAttempts: _connectAttempts,
        reconnectAttempts: _reconnectAttempts,
        backgroundedAtMs: _backgroundedAtMs,
        stateBeforeAuthRecovery: _stateBeforeAuthRecovery,
        errorMessage: _errorMessage,
      );

  bool _isSessionActive() =>
      _state != SessionState.idle &&
      _state != SessionState.closing &&
      _state != SessionState.error;

  /// Whether outbound (two-way) replies are available right now (FR-6.4).
  bool get outboundAvailable => _outbound.outboundAvailable;

  /// Whether the UI should render the Captions-Only banner (FR-12.2).
  bool get isCaptionsOnly => _outbound.isCaptionsOnly;

  void _set(SessionState next) {
    if (_state == next) return;
    _state = next;
    notifyListeners();
  }

  /// Open a session for [deviceId] in [mode] (FR-4.1). Establishes exactly one
  /// peer connection, negotiating audio sendrecv / video recvonly (AT-3), runs
  /// the capability probe (design §5.1), then goes LIVE. On repeated setup
  /// failure it transitions to ERROR with a dash-free message (FR-4.4).
  Future<void> open({
    required String deviceId,
    SessionCaptionMode mode = SessionCaptionMode.clarity,
  }) async {
    if (_isSessionActive()) {
      // Exactly one live session (FR-4.6/4.7): refuse a concurrent open.
      throw StateError('A session is already active');
    }
    _deviceId = deviceId;
    _mode = mode;
    _connectAttempts = 0;
    _reconnectAttempts = 0;
    _backgroundedAtMs = null;
    _stateBeforeAuthRecovery = null;
    _errorMessage = null;
    _media = null;
    _outbound = OutboundModeMachine(); // fresh: re-probe from scratch (FR-6.4b)
    _captions = TurnAccumulator(); // fresh caption turns for the new session
    _queued.clear();
    _sameDeviceHapticReplays = 0;

    // Take a generation token for this open(). If end() is called while we are
    // awaiting connect/probe, it bumps the token and we abandon our result
    // instead of moving a session the user ended back to live (HIGH-04).
    final int generation = ++_openGeneration;

    _set(SessionState.connecting);
    NegotiatedMedia? media;
    while (_connectAttempts < kMaxConnectAttempts && media == null) {
      _connectAttempts++;
      try {
        media = await _port.connect(deviceId);
      } on Object {
        // Any failure (SessionConnectException or an unexpected throw from the
        // binding) counts as a failed attempt against the retry budget rather
        // than escaping and stranding the state at connecting (HIGH-04).
        media = null;
      }
      if (generation != _openGeneration) return; // superseded by end()/open()
    }
    if (media == null) {
      _errorMessage = "Couldn't connect to your doorbell.";
      _set(SessionState.error);
      return;
    }
    _media = media;

    // Peer connection connected: run the capability probe (design §5.1). A
    // throw from the probe must not strand the state at probing: treat it as a
    // failed probe, which degrades the session to Captions-Only (HIGH-04).
    _set(SessionState.probing);
    bool probeOk;
    try {
      probeOk = await _port.runProbe();
    } on Object {
      probeOk = false;
    }
    if (generation != _openGeneration) return; // superseded by end()/open()
    _outbound.applyProbe(probeOk ? ProbeResult.success : ProbeResult.failure);

    _set(SessionState.live);
  }

  /// Record the outcome of an outbound injection (FR-6.4b). A failure while
  /// two-way degrades this session to Captions-Only for the remainder.
  void recordInjection({required bool success}) {
    if (!_outbound.hasProbed) return;
    _outbound.recordInjection(success: success);
    notifyListeners();
  }

  /// Apply an incoming event under the concurrency rule (FR-4.6/4.7; AT-11).
  /// Returns the decision so the caller (push handler) can act on the queue and
  /// haptics. Never opens a second session.
  ConcurrencyDecision onIncomingEvent({
    required String eventDeviceId,
    required String eventType,
  }) {
    final decision = decideConcurrency(
      activeDeviceId: activeDeviceId,
      eventDeviceId: eventDeviceId,
    );
    switch (decision.action) {
      case ConcurrencyAction.updateContextSameDevice:
        _sameDeviceHapticReplays++;
        notifyListeners();
        break;
      case ConcurrencyAction.queueDifferentDevice:
        _queued.add(QueuedEvent(deviceId: eventDeviceId, eventType: eventType));
        notifyListeners();
        break;
      case ConcurrencyAction.openAllowed:
        break;
    }
    return decision;
  }

  /// The app went to the background. The session is kept alive; a >5 minute
  /// background closes it (FR-4.3a, AT-25).
  void onBackgrounded() {
    if (_state != SessionState.live) return;
    _backgroundedAtMs = _nowMs();
    _set(SessionState.backgrounded);
  }

  /// The app returned to the foreground. Within the 5-minute window the session
  /// resumes without renegotiation (FR-4.3a, AT-25); beyond it, the session has
  /// already been closed by [tickBackground] or is closed now.
  void onForegrounded() {
    if (_state != SessionState.backgrounded) return;
    final since = _nowMs() - (_backgroundedAtMs ?? _nowMs());
    if (since <= kBackgroundSurvivalWindow.inMilliseconds) {
      _backgroundedAtMs = null;
      _set(SessionState.live); // resume without renegotiation (FR-4.3a)
    } else {
      _closeInternal();
    }
  }

  /// Poll the background timer (called by a periodic timer in the composition
  /// root; driven directly in tests). Closes the session once the 5-minute
  /// window elapses while still backgrounded (FR-4.3a, AT-25).
  void tickBackground() {
    if (_state != SessionState.backgrounded) return;
    final since = _nowMs() - (_backgroundedAtMs ?? _nowMs());
    if (since > kBackgroundSurvivalWindow.inMilliseconds) {
      _closeInternal();
    }
  }

  /// Explicitly end the session (FR-4.3): close the peer connection and release
  /// the session URL.
  Future<void> end() async {
    // Invalidate any in-flight open() so it cannot move a session the user
    // ended back to live after connect/probe resolves (HIGH-04).
    _openGeneration++;
    if (_state == SessionState.idle) return;
    try {
      await _port.close();
    } catch (_) {
      // A failing close must not throw out of end(): the user is leaving.
    }
    _reset();
    _set(SessionState.idle);
  }

  void _closeInternal() {
    _openGeneration++; // invalidate any in-flight open()
    _set(SessionState.closing);
    // Fire-and-forget close; state returns to idle when the port acknowledges.
    // A failing close must not leave the state stuck at closing or raise an
    // unhandled async error, so settle to idle on error too (HIGH-04).
    unawaited(_port.close().then((_) {
      _reset();
      _set(SessionState.idle);
    }).catchError((Object _) {
      _reset();
      _set(SessionState.idle);
    }));
  }

  void _reset() {
    _backgroundedAtMs = null;
    _stateBeforeAuthRecovery = null;
    _queued.clear();
  }

  // --- Port event handling ---
  void _onPortEvent(SessionPortEvent event) {
    switch (event) {
      case SessionPortEvent.dropped:
        _onDrop();
        break;
      case SessionPortEvent.reconnected:
        _reconnectAttempts = 0;
        if (_state == SessionState.reconnecting) _set(SessionState.live);
        break;
      case SessionPortEvent.reconnectFailed:
        _onReconnectFailed();
        break;
      case SessionPortEvent.authExpired:
        _onAuthExpired();
        break;
      case SessionPortEvent.sessionAlreadyActive:
        // The broker rejected a second session (4409). We already enforce one
        // session locally; surface nothing new, do not open a second PC.
        break;
      case SessionPortEvent.connected:
      case SessionPortEvent.connectFailed:
        // Handled synchronously in open()'s retry loop.
        break;
    }
  }

  void _onDrop() {
    if (_state == SessionState.live || _state == SessionState.backgrounded) {
      _reconnectAttempts = 0;
      _set(SessionState.reconnecting);
    }
  }

  void _onReconnectFailed() {
    if (_state != SessionState.reconnecting) return;
    _reconnectAttempts++;
    if (_reconnectAttempts >= kMaxReconnectAttempts) {
      _closeInternal(); // two failures go to CLOSING (design §5.2)
    } else {
      notifyListeners(); // stay reconnecting; another attempt will follow
    }
  }

  // --- Unified auth recovery (FR-1.5, FR-4.8; AT-12) ---

  /// The single, non-destructive recovery flow. Called when the app-to-backend
  /// session expires mid-use. It preserves the current state and shows exactly
  /// one prompt; there is no second divergent path (FR-1.5).
  void _onAuthExpired() {
    beginAuthRecovery();
  }

  /// Enter auth recovery, preserving the pre-expiry state to resume (FR-1.5).
  /// Idempotent: a second expiry while already recovering does not stack a
  /// second prompt (there is exactly one recovery flow, AT-12).
  void beginAuthRecovery() {
    if (_state == SessionState.authRecovering) return; // one prompt only
    // Only an established session can recover its auth. Entering recovery from
    // idle, connecting, probing, closing or error made no sense and let open()
    // overwrite authRecovering with probing (HIGH-04). Restrict to the states a
    // mid-use expiry can actually occur in (FR-1.5).
    const Set<SessionState> recoverable = <SessionState>{
      SessionState.live,
      SessionState.backgrounded,
      SessionState.reconnecting,
    };
    if (!recoverable.contains(_state)) return;
    _stateBeforeAuthRecovery = _state;
    _set(SessionState.authRecovering);
  }

  /// The resident re-authenticated successfully: resume the preserved state and
  /// the interrupted action (FR-1.5).
  void completeAuthRecovery({required bool success}) {
    if (_state != SessionState.authRecovering) return;
    if (success) {
      final resume = _stateBeforeAuthRecovery ?? SessionState.live;
      _stateBeforeAuthRecovery = null;
      _set(resume);
    } else {
      // Recovery declined or failed: tear the session down cleanly.
      _stateBeforeAuthRecovery = null;
      _closeInternal();
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    // Close the device binding so a disposed controller never leaves the peer
    // connection, inbound audio and cloud transcription running (CRIT-05). The
    // close is fire and forget with its own error guard: dispose() must not
    // throw, and a failing close must not surface an unhandled async error.
    unawaited(_port.close().catchError((Object _) {}));
    super.dispose();
  }
}
