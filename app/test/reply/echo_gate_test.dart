import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/reply/echo_gate.dart';
import 'package:threshold/session/session_port.dart';

void main() {
  group('EchoGate self-transcription suppression (Task 14, FR-5.6; AT-18)', () {
    test('gate is open by default; inbound audio is transcribed', () {
      final gate = EchoGate(nowMs: () => 0);
      expect(gate.isGateClosed, isFalse);
      expect(gate.shouldTranscribe, isTrue);
    });

    test('gate closes while reply audio plays (GATE_ASR_ON)', () {
      var now = 0;
      final gate = EchoGate(nowMs: () => now);
      gate.onReplyPlaybackStart();
      expect(gate.isPlaying, isTrue);
      expect(gate.isGateClosed, isTrue);
      expect(gate.shouldTranscribe, isFalse); // our own reply not transcribed
    });

    test('gate stays closed for the 300 ms tail after playback ends (AT-18)',
        () {
      var now = 1000;
      final gate = EchoGate(nowMs: () => now);
      gate.onReplyPlaybackStart();
      now = 1500; // 500 ms of playback
      gate.onReplyPlaybackEnd();
      // Immediately after end: still closed (within tail).
      expect(gate.isGateClosed, isTrue);
      now = 1500 + 299; // within the 300 ms tail
      expect(gate.isGateClosed, isTrue);
      now = 1500 + 300; // tail elapsed
      expect(gate.isGateClosed, isFalse);
      expect(gate.shouldTranscribe, isTrue);
    });

    test('the gate reopens within 300 ms and records a non-visitor gap (AT-18)',
        () {
      var now = 0;
      final gate = EchoGate(nowMs: () => now);
      gate.onReplyPlaybackStart(); // opened at 0
      now = 800;
      gate.onReplyPlaybackEnd(); // ended at 800
      now = 800 + 300; // tail fully elapsed
      final gap = gate.settle();
      expect(gap, isNotNull);
      expect(gap!.startMs, 0);
      expect(gap.endMs, 800 + kEchoTail.inMilliseconds);
      expect(gap.durationMs, 800 + 300);
      expect(gate.gaps.length, 1);
      // Gate is open again after the gap is recorded.
      expect(gate.isGateClosed, isFalse);
    });

    test('gap label is dash-free (NFR-10)', () {
      const gap = TranscriptGap(startMs: 0, endMs: 300);
      expect(gap.label.contains('\u2014'), isFalse);
      expect(gap.label.contains('\u2013'), isFalse);
    });

    test('settle before the tail elapses does not close the gap', () {
      var now = 0;
      final gate = EchoGate(nowMs: () => now);
      gate.onReplyPlaybackStart();
      now = 500;
      gate.onReplyPlaybackEnd();
      now = 500 + 100; // still within tail
      expect(gate.settle(), isNull);
      expect(gate.gaps, isEmpty);
    });

    test('a second start while playing does not stack a gate open point', () {
      var now = 100;
      final gate = EchoGate(nowMs: () => now);
      gate.onReplyPlaybackStart(); // opened at 100
      now = 200;
      gate.onReplyPlaybackStart(); // ignored while playing
      now = 300;
      gate.onReplyPlaybackEnd();
      now = 300 + 300;
      final gap = gate.settle();
      expect(gap!.startMs, 100); // original open point preserved
    });

    test('multiple reply cycles record multiple distinct gaps', () {
      var now = 0;
      final gate = EchoGate(nowMs: () => now);
      // Cycle 1
      gate.onReplyPlaybackStart();
      now = 400;
      gate.onReplyPlaybackEnd();
      now = 400 + 300;
      gate.settle();
      // Cycle 2
      now = 2000;
      gate.onReplyPlaybackStart();
      now = 2500;
      gate.onReplyPlaybackEnd();
      now = 2500 + 300;
      gate.settle();
      expect(gate.gaps.length, 2);
      expect(gate.gaps[0].startMs, 0);
      expect(gate.gaps[1].startMs, 2000);
    });

    test('WebRTC echo cancellation is enabled on the inbound track (FR-5.6)',
        () {
      // The documented device-bound constraint complements the software gate.
      expect(kInboundAudioConstraints['echoCancellation'], isTrue);
    });
  });
}
