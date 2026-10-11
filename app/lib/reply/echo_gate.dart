// Self-transcription echo gating (Task 14, FR-5.6; AT-18). While reply audio is
// playing at the door, the doorbell microphone returns our own synthesized
// speech on the inbound leg. If that were transcribed, the resident would see
// their own reply captioned as if the visitor said it. FR-5.6 requires the app
// to:
//   1. gate the caption pipeline while reply audio plays (GATE_ASR_ON),
//   2. keep the gate closed for a 300 ms tail after playback ends (GATE_OFF),
//   3. mark the gated interval in the transcript as a non-visitor gap so the
//      resident knows something between the reply and the next caption may have
//      been missed (design §5.3),
//   4. additionally enable WebRTC echo cancellation on the inbound track.
//
// The WebRTC echo-cancellation constraint (`echoCancellation: true`) is applied
// in the WebView getUserMedia/track constraints and is documented in the port
// (device-bound). This file owns the pure gate logic and the transcript gap
// marking so the open/close timing and the gap are exhaustively unit-testable
// with an injectable clock, no audio and no device required.

import 'package:flutter/foundation.dart';

/// The 300 ms tail the gate stays closed after playback ends (FR-5.6).
const Duration kEchoTail = Duration(milliseconds: 300);

/// Monotonic clock in milliseconds, injectable for deterministic tests.
typedef NowMs = int Function();

/// A marked interval in the transcript where captions were intentionally
/// suppressed because our own reply was playing (design §5.3 "non-visitor gap").
@immutable
class TranscriptGap {
  const TranscriptGap({required this.startMs, required this.endMs});

  final int startMs;
  final int endMs;

  int get durationMs => endMs - startMs;

  /// A dash-free label the transcript UI shows for the gap (NFR-10).
  String get label => 'Reply playing. Visitor audio not captioned.';
}

/// The gate that suppresses the caption pipeline during reply playback (FR-5.6).
/// It is closed while a reply plays and for a 300 ms tail afterwards; while
/// closed, [shouldTranscribe] returns false so inbound audio is dropped from
/// captioning. Each open/close cycle records a [TranscriptGap].
class EchoGate {
  EchoGate({NowMs? nowMs})
      : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final NowMs _nowMs;

  bool _playing = false;
  int? _gateOpenedAtMs; // when the gate closed captioning (reply start)
  int? _playbackEndedAtMs; // when playback ended; tail counts from here
  final List<TranscriptGap> _gaps = <TranscriptGap>[];

  /// All recorded non-visitor gaps (assertion + transcript source).
  List<TranscriptGap> get gaps => List.unmodifiable(_gaps);

  /// True while reply audio is actively playing.
  bool get isPlaying => _playing;

  /// Reply playback started: close the gate (GATE_ASR_ON, FR-5.6).
  void onReplyPlaybackStart() {
    if (_playing) return; // already gated; do not stack
    _playing = true;
    _playbackEndedAtMs = null;
    _gateOpenedAtMs = _nowMs();
  }

  /// Reply playback ended: begin the 300 ms tail (GATE_OFF+300ms, FR-5.6). The
  /// gate stays closed until the tail elapses; call [isGateClosed]/[settle] to
  /// evaluate the current instant.
  void onReplyPlaybackEnd() {
    if (!_playing) return;
    _playing = false;
    _playbackEndedAtMs = _nowMs();
  }

  /// Whether the caption pipeline is currently gated closed (FR-5.6): closed
  /// while playing, and for the 300 ms tail after playback ends. Closing the gap
  /// (recording the TranscriptGap) happens in [settle] once the tail elapses.
  bool get isGateClosed {
    if (_playing) return true;
    final endedAt = _playbackEndedAtMs;
    if (endedAt == null) return false;
    return _nowMs() - endedAt < kEchoTail.inMilliseconds;
  }

  /// Whether inbound audio should be transcribed right now (FR-5.6). The inverse
  /// of [isGateClosed].
  bool get shouldTranscribe => !isGateClosed;

  /// Reopen the gate WITHOUT recording a gap. Used when a reply never actually
  /// played (TTS/injection failed before any audio reached the door), so there
  /// is no gated visitor interval to mark (FR-5.6). Idempotent.
  void cancel() {
    _playing = false;
    _gateOpenedAtMs = null;
    _playbackEndedAtMs = null;
  }

  /// Evaluate the tail: if playback has ended and the 300 ms tail has fully
  /// elapsed, reopen the gate and record the non-visitor gap for the transcript
  /// (design §5.3). Idempotent; safe to poll. Returns the gap if one was closed.
  TranscriptGap? settle() {
    if (_playing) return null;
    final endedAt = _playbackEndedAtMs;
    final openedAt = _gateOpenedAtMs;
    if (endedAt == null || openedAt == null) return null;
    if (_nowMs() - endedAt < kEchoTail.inMilliseconds) return null;
    // Tail elapsed: reopen the gate and record the gap (reply start .. tail end).
    final gap = TranscriptGap(
        startMs: openedAt, endMs: endedAt + kEchoTail.inMilliseconds);
    _gaps.add(gap);
    _gateOpenedAtMs = null;
    _playbackEndedAtMs = null;
    return gap;
  }
}
