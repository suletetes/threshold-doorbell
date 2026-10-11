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
        home: RecordingNoticeScreen(
            controller: c, onAcknowledged: () => acked = true),
      ));
      await tester.pump();
      expect(find.textContaining('turns what your visitor says into text'),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('recording-notice-ack')));
      await tester.pumpAndSettle();
      expect(c.isAcknowledged, isTrue);
      expect(acked, isTrue);
    });
  });

  group('ComplianceFallbackDialog (Task 21, FR-14.3a; AT-14)', () {
    testWidgets('continue keeps captions on, honored for the session',
        (tester) async {
      final c =
          RecordingNoticeController(FakeConsentStore(audibleNotice: true));
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

    testWidgets('disable turns off transcription for the session',
        (tester) async {
      final c =
          RecordingNoticeController(FakeConsentStore(audibleNotice: true));
      await c.load();
      c.beginSession();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ComplianceFallbackDialog(controller: c)),
      ));
      await tester.pump();
      await tester
          .tap(find.byKey(const ValueKey('compliance-disable-transcription')));
      await tester.pump();
      expect(
        c.resolveSessionStart(outboundAvailable: false),
        SessionNoticeAction.disableTranscription,
      );
    });

    testWidgets(
        'it does NOT remember the choice as default by default (MED-06)',
        (tester) async {
      final c =
          RecordingNoticeController(FakeConsentStore(audibleNotice: true));
      await c.load();
      c.beginSession();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ComplianceFallbackDialog(controller: c)),
      ));
      await tester.pump();
      // Choose WITHOUT ticking the remember checkbox.
      await tester
          .tap(find.byKey(const ValueKey('compliance-disable-transcription')));
      await tester.pump();
      // The session choice is honored, but the persisted default is untouched:
      // a one-time choice must not silently become the legal default (MED-06).
      expect(c.defaultComplianceChoice, isNull);
    });

    testWidgets('ticking remember persists the choice as the default (MED-06)',
        (tester) async {
      final c =
          RecordingNoticeController(FakeConsentStore(audibleNotice: true));
      await c.load();
      c.beginSession();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ComplianceFallbackDialog(controller: c)),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('compliance-remember')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('compliance-continue')));
      await tester.pump();
      expect(c.defaultComplianceChoice, ComplianceChoice.continueWithoutNotice);
    });

    testWidgets('it pops with the chosen result (MED-06)', (tester) async {
      final c =
          RecordingNoticeController(FakeConsentStore(audibleNotice: true));
      await c.load();
      c.beginSession();
      ComplianceChoice? popped;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                popped = await showDialog<ComplianceChoice>(
                  context: context,
                  builder: (_) => ComplianceFallbackDialog(controller: c),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('compliance-fallback')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('compliance-continue')));
      await tester.pumpAndSettle();
      // The dialog closed and returned its result (MED-06): it no longer hangs.
      expect(find.byKey(const ValueKey('compliance-fallback')), findsNothing);
      expect(popped, ComplianceChoice.continueWithoutNotice);
    });
  });
}
