// Recording notice presentation (UI/UX audit section 5: "adopt the shared
// components so the consent and permission surfaces match the rest of the app").
// This screen was a raw fontSize of 18 with a raw height of 1.4 and a stock
// button at the bottom of a bare Column.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/consent/recording_notice.dart';
import 'package:threshold/consent/recording_notice_controller.dart';
import 'package:threshold/consent/recording_notice_screen.dart';
import 'package:threshold/design/colors.dart';
import 'package:threshold/design/components/components.dart';
import 'package:threshold/design/theme.dart';
import 'package:threshold/design/tokens.dart';

Future<RecordingNoticeController> _controller(
    {bool audibleNotice = false}) async {
  final c =
      RecordingNoticeController(FakeConsentStore(audibleNotice: audibleNotice));
  await c.load();
  return c;
}

Widget _host(RecordingNoticeController c, {VoidCallback? onAck}) => MaterialApp(
      theme: ThresholdTheme.light(),
      home: RecordingNoticeScreen(controller: c, onAcknowledged: onAck),
    );

void main() {
  group('The notice screen uses the design system (audit section 5)', () {
    testWidgets('it has a section header and the notice on the type scale',
        (tester) async {
      final c = await _controller();
      await tester.pumpWidget(_host(c));
      await tester.pump();
      expect(find.byType(SectionHeader), findsOneWidget);
      expect(find.text(kRecordingNoticeHeading), findsOneWidget);
      final context = tester.element(find.byType(RecordingNoticeScreen));
      final expected = Theme.of(context).textTheme.bodyLarge!;
      expect(
        tester.widget<Text>(find.text(kRecordingNoticeText)).style?.fontSize,
        expected.fontSize,
      );
    });

    testWidgets('acknowledging is the hero action, not a stock button',
        (tester) async {
      final c = await _controller();
      await tester.pumpWidget(_host(c));
      await tester.pump();
      expect(find.byType(PrimaryActionCard), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('recording-notice-ack')))
            .height,
        greaterThanOrEqualTo(PrimaryActionCard.minimumHeight),
      );
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('it still acknowledges on tap (FR-14.1, AT-14)',
        (tester) async {
      final c = await _controller();
      var acked = false;
      await tester.pumpWidget(_host(c, onAck: () => acked = true));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('recording-notice-ack')));
      await tester.pumpAndSettle();
      expect(c.isAcknowledged, isTrue);
      expect(acked, isTrue);
    });

    testWidgets('the notice keeps its live region and label (G4)',
        (tester) async {
      final handle = tester.ensureSemantics();
      final c = await _controller();
      await tester.pumpWidget(_host(c));
      await tester.pump();
      expect(find.bySemanticsLabel(kRecordingNoticeText), findsOneWidget);
      expect(find.bySemanticsLabel('I understand'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('long notice copy scrolls instead of overflowing at 200% scale',
        (tester) async {
      final c = await _controller();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThresholdTheme.light(),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2.0)),
              child: RecordingNoticeScreen(controller: c),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('the heading copy is dash-free (NFR-10)', (tester) async {
      expect(kRecordingNoticeHeading.contains('\u2014'), isFalse);
      expect(kRecordingNoticeHeading.contains('\u2013'), isFalse);
    });
  });

  group('The compliance fallback dialog carries meaning (FR-14.3a)', () {
    testWidgets('it shows a warning-role icon', (tester) async {
      final c = await _controller(audibleNotice: true);
      c.beginSession();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThresholdTheme.light(),
          home: Scaffold(body: ComplianceFallbackDialog(controller: c)),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.volume_off_outlined), findsOneWidget);
      final context = tester.element(find.byIcon(Icons.volume_off_outlined));
      expect(
        tester.widget<Icon>(find.byIcon(Icons.volume_off_outlined)).color,
        ThresholdSemanticColors.of(context).warning,
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.volume_off_outlined)).size,
        Spacing.space8,
      );
    });

    testWidgets('both choices still resolve the session the same way',
        (tester) async {
      for (final choice in <(String, SessionNoticeAction)>[
        ('compliance-continue', SessionNoticeAction.continueWithoutNotice),
        (
          'compliance-disable-transcription',
          SessionNoticeAction.disableTranscription
        ),
      ]) {
        final c = await _controller(audibleNotice: true);
        c.beginSession();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThresholdTheme.light(),
            home: Scaffold(body: ComplianceFallbackDialog(controller: c)),
          ),
        );
        await tester.pump();
        await tester.tap(find.byKey(ValueKey(choice.$1)));
        await tester.pump();
        expect(c.resolveSessionStart(outboundAvailable: false), choice.$2);
      }
    });
  });
}
