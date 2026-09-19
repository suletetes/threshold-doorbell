import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/alerts/push_receiver.dart';
import 'package:threshold/connectivity/connectivity_state.dart';
import 'package:threshold/perf/degradation_matrix.dart';
import 'package:threshold/reply/ondevice_suggestions.dart';
import 'package:threshold/reply/reply_suggestions.dart';
import 'package:threshold/vision/privacy_zone_geometry.dart';
import 'package:threshold/vision/vision_port.dart';

void main() {
  group('Degradation matrix invariants (Task 26, NFR-5, FR-15.4; AT-20)', () {
    test('every dependency has a defined, non-silent degradation (NFR-5)', () {
      final matrix = degradationMatrix();
      expect(matrix.length, Dependency.values.length);
      for (final d in matrix) {
        // No failure is silent: a surfaced explanation always exists (NFR-5).
        expect(d.isSurfaced, isTrue, reason: '${d.dependency} must surface a message');
        // No session crashes on any dependency failure (NFR-5).
        expect(d.sessionSurvives, isTrue, reason: '${d.dependency} must not crash the session');
      }
    });

    test('all degradation messages are dash-free (NFR-10)', () {
      for (final d in degradationMatrix()) {
        expect(d.userMessage.contains('\u2014'), isFalse);
        expect(d.userMessage.contains('\u2013'), isFalse);
      }
    });
  });

  group('Bedrock failure -> fixed safe replies (FR-7.3, FR-7.5; AT-20)', () {
    test('with no contextual suggestions the reply bar still has the safe set', () {
      // Simulate Bedrock returning nothing (timeout/error).
      final buttons = composeReplyButtons(const <String>[]);
      expect(buttons, isNotEmpty);
      for (final safe in kFixedSafeReplies) {
        expect(buttons.contains(safe), isTrue);
      }
      final deg = degradationFor(Dependency.bedrock);
      expect(deg.sessionSurvives, isTrue);
    });
  });

  group('Transcribe failure -> notice, no mid-session mode switch (AT-20)', () {
    test('the defined degradation keeps the session and suggests Privacy next', () {
      final deg = degradationFor(Dependency.transcribe);
      expect(deg.sessionSurvives, isTrue);
      expect(deg.userMessage.contains('Privacy Mode'), isTrue);
      expect(deg.fallbackDescription.contains('without switching mode'), isTrue);
    });
  });

  group('Push failure -> foreground poll fallback (FR-3.5; AT-20)', () {
    test('an unavailable push receiver does not silently drop the alert', () {
      final receiver = FixturePushReceiver(pushAvailable: false);
      final delivered = receiver.deliver(const PushAlert(
        type: 'person_detected',
        timestamp: '2026-01-01T00:00:00Z',
        deviceId: 'dev-1',
        thumbnailUrl: null,
      ));
      // deliver returns false so the caller falls back to the poll (FR-3.5).
      expect(delivered, isFalse);
      final deg = degradationFor(Dependency.push);
      expect(deg.sessionSurvives, isTrue);
    });
  });

  group('Visual processor failure -> presence from events alone (FR-5.4; AT-20)', () {
    test('an unavailable vision port leaves captions unaffected', () {
      final vision = FixtureVision(available: false);
      expect(vision.isAvailable, isFalse);
      // With no admitted cues, visual presence is false; presence then relies on
      // the event condition alone (FR-5.4). No frame is ever transmitted.
      const frame = VisionFrame(<VisionCue>[]);
      expect(visualPersonPresent(frame, const <Rect>[]), isFalse);
      expect(vision.framesTransmitted, 0);
      final deg = degradationFor(Dependency.visualProcessor);
      expect(deg.sessionSurvives, isTrue);
    });
  });

  group('Backend/signaling failure -> new sessions blocked, history usable (FR-15.4; AT-20)', () {
    test('backend unreachable blocks openSession but keeps cached history', () {
      const state = ConnectivityState.backendUnreachableOnline;
      final open = availabilityOf(NetworkAction.openSession, state);
      expect(open.allowed, isFalse);
      expect(open.reason, UnavailableReason.backendUnreachable);
      final history = availabilityOf(NetworkAction.readCachedHistory, state);
      expect(history.allowed, isTrue); // cached history usable (FR-15.4)
      final deg = degradationFor(Dependency.backendSignaling);
      expect(deg.sessionSurvives, isTrue); // active session not crashed
    });
  });
}
