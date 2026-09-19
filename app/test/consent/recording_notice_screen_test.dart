import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/consent/recording_notice.dart';
import 'package:threshold/consent/recording_notice_controller.dart';
import 'package:threshold/consent/recording_notice_screen.dart';

void main() {
  group('RecordingNoticeScreen (Task 21, FR-14.1; AT-14)', () {
    testWidgets('shows the notice and acknowledges on tap', (tester) async {
      final store = FakeConsentStore();
      final c = RecordingNoticeController(store);
      await c.load();
      var acked = false;
      await tester.pumpWidget(MaterialApp(
        home: RecordingNoticeScreen(controller: c, onAcknowledged: () => acked = true),
      ));
      await tester.pump();
      expect(find.textContaining('turns what your visitor says into text'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('recording-notice-ack')));
      await tester.pumpAndSettle();
      expect(c.isAcknowledged, isTrue);
      expect(acked, isTrue);
    });
  });

  group('ComplianceFallbackDialog (Task 21, FR-14.3a; AT-14)', () {
    testWidgets('continue keeps captions on, honored for the session', (tester) async {
      final c = RecordingNoticeController(FakeConsentStore(audibleNotice: true));
      await c.load();
      c.beginSession();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ComplianceFallbackDialog(controller: c)),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('compliance-continue')));
      await tester.pump();
      expect(
        c.resolveSessionStart(outboundAvailable: false),
        SessionNoticeAction.continueWithoutNotice,
      );
    });

    testWidgets('disable turns off transcription for the session', (tester) async {
      final c = RecordingNoticeController(FakeConsentStore(audibleNotice: true));
      await c.load();
      c.beginSession();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ComplianceFallbackDialog(controller: c)),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('compliance-disable-transcription')));
      await tester.pump();
      expect(
        c.resolveSessionStart(outboundAvailable: false),
        SessionNoticeAction.disableTranscription,
      );
    });
  });
}
