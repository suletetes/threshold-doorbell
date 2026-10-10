// Reply controller (Task 15, FR-6.1, FR-6.3, FR-6.5, FR-7.2, FR-7.5, G3; AT-5,
// AT-7). Drives the reply lifecycle of design §5.3:
//
//   COMPOSING -> SYNTHESIZING -> GATE_ASR_ON -> SPEAKING_AT_DOOR -> GATE_OFF(+300ms) -> SENT
//                     | tts fail                      | inject fail
//                     v                               v
//               ERROR(retry once)      DEGRADE to captions-only + banner
//
// It ties the ReplyPort (TTS + injection), the sticky OutboundModeMachine
// (FR-6.4b degrade on injection failure), and the EchoGate (FR-5.6 gate the
// caption pipeline while speaking). Sent replies are appended to the transcript
// as `resident` turns with source `template` or `freetext` (FR-6.5). Duplicate
// submission of the same reply is disabled while it is speaking (FR-6.3).
//
// A ChangeNotifier so a Riverpod provider rebuilds the reply bar; the reply
// lifecycle is fully unit- and widget-testable with the fakes.

import 'package:flutter/foundation.dart';

import 'echo_gate.dart';
import 'outbound_mode.dart';
import 'reply_port.dart';

/// The visible state of the reply bar / reply-in-flight (design §5.3).
enum ReplyState {
  /// The resident is composing (idle reply bar).
  composing,

  /// Synthesizing speech from text (TTS).
  synthesizing,

  /// Reply audio is playing at the door; "Speaking at your door" is shown and
  /// resubmission of the same reply is disabled (FR-6.3).
  speakingAtDoor,

  /// The reply finished and was appended to the transcript (FR-6.5).
  sent,

  /// The reply failed (TTS after a retry). The bar returns to composing.
  error,
}

/// Where a sent reply came from (FR-6.5). Mirrors design §3 TurnSource.
enum ReplySource { template, freetext }

/// A resident turn appended to the transcript (FR-6.5).
@immutable
class ResidentTurn {
  const ResidentTurn({required this.text, required this.source, required this.atMs});
  final String text;
  final ReplySource source;
  final int atMs;
}

typedef NowMs = int Function();

/// Waits [d] before continuing; injectable so the 300 ms echo tail is
/// deterministic under `flutter test` (a fake advances the clock instead of
/// sleeping).
typedef DelayFn = Future<void> Function(Duration d);

class ReplyController extends ChangeNotifier {
  ReplyController({
    required ReplyPort port,
    required OutboundModeMachine outbound,
    EchoGate? echoGate,
    NowMs? nowMs,
    DelayFn? delay,
  })  : _port = port,
        _outbound = outbound,
        _echoGate = echoGate,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
        _delay = delay ?? Future<void>.delayed;

  final ReplyPort _port;
  final OutboundModeMachine _outbound;
  final EchoGate? _echoGate;
  final NowMs _nowMs;
  final DelayFn _delay;

  /// The transcript gaps recorded by the echo gate across this controller's
  /// replies (FR-5.6, AT-18). Exposed so the transcript/session can persist and
  /// tests can assert the gate marking actually fired in production.
  List<TranscriptGap> get echoGaps => _echoGate?.gaps ?? const <TranscriptGap>[];

  ReplyState _state = ReplyState.composing;
  String? _inFlightText; // the reply currently being spoken (FR-6.3)
  String? _errorMessage;
  final List<ResidentTurn> _turns = <ResidentTurn>[];

  ReplyState get state => _state;
  String? get inFlightText => _inFlightText;
  String? get errorMessage => _errorMessage;

  /// Resident turns appended so far (FR-6.5). The transcript source of truth.
  List<ResidentTurn> get turns => List.unmodifiable(_turns);

  /// Whether the reply bar is shown at all. Hidden when outbound is unavailable
  /// (Captions-Only banner shown instead, FR-6.4 / design §5.3 last bullet).
  bool get replyBarVisible => _outbound.outboundAvailable;

  /// Whether inbound audio should be transcribed right now (FR-5.6). False while
  /// our own reply is playing at the door (and for the 300 ms echo tail), so the
  /// composition root can gate SessionController.ingestCaption on this and never
  /// caption our synthesized speech as the visitor. True when there is no gate.
  bool get shouldTranscribe => _echoGate?.shouldTranscribe ?? true;

  /// Whether a given [text] can be submitted right now. False while a reply is
  /// in flight (no duplicate/parallel send, FR-6.3) or when outbound is
  /// unavailable.
  bool canSend(String text) {
    if (!_outbound.outboundAvailable) return false;
    if (_state == ReplyState.synthesizing || _state == ReplyState.speakingAtDoor) {
      return false;
    }
    return text.trim().isNotEmpty;
  }

  /// Speak a reply at the door (FR-6.1). Drives the full design §5.3 lifecycle,
  /// including TTS retry-once, echo-gating during playback, injection-failure
  /// degrade (FR-6.4b), and appending the resident turn on success (FR-6.5).
  Future<void> send(String text, {required ReplySource source}) async {
    final trimmed = text.trim();
    if (!canSend(trimmed)) return; // guards duplicate/empty/unavailable
    _inFlightText = trimmed;
    _errorMessage = null;

    // GATE_ASR_ON: close the caption gate BEFORE reply audio plays so the
    // doorbell's return of our own synthesized speech is never captioned as the
    // visitor (FR-5.6). The gate stays closed through synthesis and playback.
    _echoGate?.onReplyPlaybackStart();

    // SYNTHESIZING: shown while TTS runs. SPEAKING_AT_DOOR is entered only when
    // the port signals playback actually started (HIGH-05), so the bar does not
    // claim to be speaking before any audio reached the door.
    _set(ReplyState.synthesizing);

    SpeakOutcome outcome;
    try {
      // speak() resolves only after reply audio has finished playing. On a TTS
      // failure, retry exactly once (design §5.3).
      outcome = await _port.speak(trimmed, onPlaybackStart: _onPlaybackStarted);
      if (outcome == SpeakOutcome.ttsFailed) {
        outcome = await _port.speak(trimmed, onPlaybackStart: _onPlaybackStarted);
      }
    } catch (_) {
      // The binding threw (e.g. no device). Treat it as a reply that never
      // played: reopen the gate, clear the in-flight text, and surface an error
      // instead of leaving the gate closed and the bar stuck at speaking
      // forever (HIGH-05, probe P2).
      _abandonGate();
      _inFlightText = null;
      _errorMessage = 'Could not play the reply. Please try again.';
      _set(ReplyState.error);
      return;
    }

    switch (outcome) {
      case SpeakOutcome.ttsFailed:
        // Never spoke: reopen the gate immediately, no gap to mark.
        _abandonGate();
        _inFlightText = null;
        _errorMessage = 'Could not play the reply. Please try again.';
        _set(ReplyState.error);
        return;
      case SpeakOutcome.injectionFailed:
        // Degrade this session to Captions-Only for the remainder (FR-6.4b).
        _abandonGate();
        _outbound.recordInjection(success: false);
        _inFlightText = null;
        _errorMessage = 'Spoken replies are no longer available in this session.';
        _set(ReplyState.error);
        return;
      case SpeakOutcome.spoken:
        break;
    }

    // Record the successful injection so the sticky machine stays two-way.
    _outbound.recordInjection(success: true);

    // GATE_OFF(+300 ms): playback finished. Hold the gate closed for the 300 ms
    // tail, then settle() to reopen it AND record the non-visitor transcript gap
    // (FR-5.6, AT-18). This is the wiring the audit found missing: previously
    // the gate opened and closed in one synchronous tick and settle() never ran.
    _echoGate?.onReplyPlaybackEnd();
    await _settleEchoTail();

    // SENT: append the resident turn to the transcript (FR-6.5).
    _turns.add(ResidentTurn(text: trimmed, source: source, atMs: _nowMs()));
    _inFlightText = null;
    _set(ReplyState.sent);
  }

  /// Enter SPEAKING_AT_DOOR when the port reports reply audio actually began
  /// playing (HIGH-05). Only transitions from SYNTHESIZING so a late or spurious
  /// callback cannot move a failed/reset reply back to speaking.
  void _onPlaybackStarted() {
    if (_state == ReplyState.synthesizing) _set(ReplyState.speakingAtDoor);
  }

  /// Hold the gate closed for the 300 ms echo tail, then settle it so the gap is
  /// recorded (FR-5.6, AT-18). Uses the injectable delay/clock for determinism.
  Future<void> _settleEchoTail() async {
    final gate = _echoGate;
    if (gate == null) return;
    await _delay(kEchoTail);
    gate.settle();
  }

  /// Reopen the gate after a failed reply without recording a gap: playback
  /// never happened, so there is no gated visitor interval to mark.
  void _abandonGate() {
    _echoGate?.cancel();
  }

  /// Return the bar to the composing state after a sent/error reply.
  void reset() {
    if (_state == ReplyState.sent || _state == ReplyState.error) {
      _errorMessage = null;
      _set(ReplyState.composing);
    }
  }

  void _set(ReplyState next) {
    _state = next;
    notifyListeners();
  }
}
