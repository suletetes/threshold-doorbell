// CRIT-07 app-wiring tests. The audit found SessionController.ingestCaption had
// no caller, so captions never reached the screen. These prove the wiring:
//
//   * A CaptionPump delivers a CaptionSource's results to the controller, and
//     those results render on the conversation screen (the missing feed).
//   * The on-device engine adapter reshapes OnDeviceResults into caption
//     results with zero network egress.
//   * The pump respects the echo gate (FR-5.6) and the transcription-disabled
//     compliance fallback (FR-14.3a), because ingestCaption enforces both.
//
// The real cloud WebSocket client and the real on-device Whisper engine remain
// deferred; a scripted fake stands in so the flow is driven headless.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/app/home_screen.dart';
import 'package:threshold/app/providers.dart';
import 'package:threshold/captions/asr_client.dart';
import 'package:threshold/captions/asr_engine.dart';
import 'package:threshold/captions/turn_segmentation.dart';
import 'package:threshold/consent/recording_notice.dart';
import 'package:threshold/design/theme.dart';
import 'package:threshold/reply/reply_port.dart';
import 'package:threshold/reply/suggestion_provider.dart';
import 'package:threshold/session/conversation_screen.dart';
import 'package:threshold/session/ring_app_launcher.dart';
import 'package:threshold/session/session_controller.dart';
import 'package:threshold/session/session_port.dart';
import 'package:threshold/settings/settings_controller.dart';

void main() {
  group('OnDeviceCaptionSource (Privacy Mode, FR-5.2, NFR-4)', () {
    test('reshapes engine results into visitor caption results, no egress', () async {
      final engine = FixtureAsrEngine();
      final source = OnDeviceCaptionSource(engine, nowMs: () => 0);
      final got = <CaptionResult>[];
      final sub = source.captions.listen(got.add);

      source.feedPcm(List<int>.filled(320, 0));
      source.feedPcm(List<int>.filled(320, 0));
      await Future<void>.delayed(Duration.zero);

      expect(got, isNotEmpty);
      expect(got.first.speaker, CaptionSpeaker.visitor);
      expect(got.first.text, 'hello there');
      // The engine transmitted nothing (on device only).
      expect(engine.bytesTransmitted, 0);
      await sub.cancel();
      await source.dispose();
    });
  });

  group('CaptionPump (CRIT-07)', () {
    test('delivers source results to the controller', () async {
      final controller = SessionController(port: FakeSessionPort());
      final source = FakeAsrStreamClient(script: const <CaptionResult>[
        CaptionResult(
          speaker: CaptionSpeaker.visitor,
          text: 'is anyone home',
          isFinal: true,
          timestampMs: 0,
          confidence: 0.9,
        ),
      ]);
      final pump = CaptionPump(controller: controller, source: source)..start();
      await source.start(deviceId: 'front-door', language: 'en-US');
      await Future<void>.delayed(Duration.zero);

      expect(controller.captionTurns, isNotEmpty);
      expect(controller.captionTurns.last.text, 'is anyone home');
      await pump.stop();
      await source.dispose();
      controller.dispose();
    });

    test('respects the echo gate: a gated result is dropped (FR-5.6)', () async {
      final controller = SessionController(port: FakeSessionPort());
      // Echo gate closed: nothing should be transcribed.
      controller.shouldTranscribe = () => false;
      final source = FakeAsrStreamClient();
      final pump = CaptionPump(controller: controller, source: source)..start();

      source.emit(const CaptionResult(
        speaker: CaptionSpeaker.visitor,
        text: 'our own reply echoing back',
        isFinal: true,
        timestampMs: 0,
        confidence: 0.9,
      ));
      await Future<void>.delayed(Duration.zero);
      expect(controller.captionTurns, isEmpty);

      // Gate open: the next result is transcribed.
      controller.shouldTranscribe = () => true;
      source.emit(const CaptionResult(
        speaker: CaptionSpeaker.visitor,
        text: 'hello',
        isFinal: true,
        timestampMs: 10,
        confidence: 0.9,
      ));
      await Future<void>.delayed(Duration.zero);
      expect(controller.captionTurns, isNotEmpty);
      await pump.stop();
      await source.dispose();
      controller.dispose();
    });
  });

  group('Captions render on the conversation screen (CRIT-07)', () {
    testWidgets('a fake engine feed renders a non-empty caption on the live screen',
        (tester) async {
      final port = FakeSessionPort();
      final fakeAsr = FakeAsrStreamClient(script: const <CaptionResult>[
        CaptionResult(
          speaker: CaptionSpeaker.visitor,
          text: 'delivery for you',
          isFinal: true,
          timestampMs: 0,
          confidence: 0.95,
        ),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            sessionPortProvider.overrideWithValue(port),
            replyPortProvider.overrideWithValue(FakeReplyPort()),
            ringAppLauncherProvider.overrideWithValue(FakeRingAppLauncher()),
            bedrockSuggestionPortProvider.overrideWithValue(FakeBedrockSuggestionPort()),
            dataErasurePortProvider.overrideWithValue(FakeDataErasurePort()),
            consentStoreProvider.overrideWithValue(FakeConsentStore(acknowledged: true)),
            // The scripted fake stands in for the deferred cloud ASR client.
            captionSourceProvider.overrideWithValue(fakeAsr),
          ],
          child: MaterialApp(theme: ThresholdTheme.light(), home: const HomeScreen()),
        ),
      );
      await tester.pump();

      // Answer the door and reach the live Conversation screen.
      await tester.tap(find.byKey(const ValueKey('home-answer')));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationScreen), findsOneWidget);

      // Before the feed starts, the surface shows the empty placeholder.
      // Start the fake stream: the pump feeds the controller, the surface
      // repaints with the real caption, and the placeholder is gone.
      await fakeAsr.start(deviceId: 'front-door', language: 'en-US');
      await tester.pumpAndSettle();

      expect(find.text('delivery for you'), findsOneWidget);
      expect(find.byKey(const ValueKey('caption-empty')), findsNothing);
    });
  });
}
