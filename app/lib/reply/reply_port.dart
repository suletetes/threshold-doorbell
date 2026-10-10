// Reply synthesis + injection port (Task 15, FR-6.1, FR-6.2; AT-5). The defining
// capability: a resident's reply is synthesized to speech (flutter_tts
// synthesizeToFile) and injected into the OUTBOUND WebRTC audio track so it is
// audible at the doorbell (AudioContext -> MediaStreamAudioDestinationNode ->
// RTCRtpSender.replaceTrack, ARCH-1). Both the TTS engine and the WebView
// injection are device/Ring bound and NOT available in this sandbox, so they sit
// behind this ReplyPort interface. The live binding is created in the
// composition root; the ReplyController and reply bar depend on the interface,
// and a FakeReplyPort drives the reply lifecycle under `flutter test`.

import 'dart:async';

/// The outcome of speaking one reply at the door.
enum SpeakOutcome {
  /// Synthesis and injection both succeeded; audio was audible at the door.
  spoken,

  /// Synthesis (TTS) failed. Design §5.3: retry once, then error.
  ttsFailed,

  /// Injection into the outbound track failed. Design §5.3: degrade the session
  /// to Captions-Only for the remainder (FR-6.4b).
  injectionFailed,
}

/// Speaks a resident reply at the door (FR-6.1, FR-6.2). Async so the live TTS
/// synthesize-to-file and the injection round-trip can be awaited; the fake
/// resolves deterministically.
abstract class ReplyPort {
  /// Synthesize [text] and inject it into the outbound audio track. Returns the
  /// outcome so the ReplyController can drive the design §5.3 lifecycle.
  ///
  /// [onPlaybackStart] fires once, when reply audio actually begins playing at
  /// the door, so the controller enters SPEAKING_AT_DOOR on real playback
  /// rather than optimistically before synthesis (HIGH-05). It is not called
  /// when synthesis fails before any audio plays.
  Future<SpeakOutcome> speak(String text, {void Function()? onPlaybackStart});
}

/// Deterministic fake. Tests script the outcome (and can script a first TTS
/// failure then success to exercise the retry-once rule of design §5.3).
class FakeReplyPort implements ReplyPort {
  FakeReplyPort({List<SpeakOutcome>? plan})
      : _plan = List<SpeakOutcome>.from(
            plan ?? const <SpeakOutcome>[SpeakOutcome.spoken]);

  final List<SpeakOutcome> _plan;

  /// Every text passed to [speak], in order (assertion helper).
  final List<String> spokenTexts = <String>[];
  int speakCalls = 0;

  @override
  Future<SpeakOutcome> speak(String text,
      {void Function()? onPlaybackStart}) async {
    speakCalls++;
    spokenTexts.add(text);
    final outcome = _plan.isEmpty ? SpeakOutcome.spoken : _plan.removeAt(0);
    // Playback only begins when synthesis succeeded (not a TTS failure).
    if (outcome != SpeakOutcome.ttsFailed) onPlaybackStart?.call();
    return outcome;
  }
}
