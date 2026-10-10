// Captions-Only presentation (UI/UX audit section 3.6: the banner was one of the
// four ad hoc status treatments, hand-rolled from a 0xFF2A3A4A fill picked by eye,
// a raw radius, a raw font size, and an outlined button with hardcoded white
// borders. Section 5 asked specifically for that action to get an icon and proper
// button weight).
//
// The pre-existing captions_only_screen_test.dart pins the FR-12 behavior. This
// file pins the presentation, and re-asserts that adopting the shared component
// did not disturb the exact FR-12.2 copy or the FR-12.3 action.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/captions/turn_segmentation.dart';
import 'package:threshold/design/colors.dart';
import 'package:threshold/design/components/components.dart';
import 'package:threshold/design/tokens.dart';
import 'package:threshold/session/captions_only_screen.dart';
import 'package:threshold/session/conversation_screen.dart';
import 'package:threshold/session/ring_app_launcher.dart';
import 'package:threshold/session/session_controller.dart';
import 'package:threshold/session/session_port.dart';
import 'package:threshold/session/watermark_safe_area.dart';
import 'package:threshold/settings/settings_state.dart';

Future<(SessionController, FakeSessionPort)> _captionsOnly() async {
  final port = FakeSessionPort(probeSucceeds: false);
  final c = SessionController(port: port);
  await c.open(deviceId: 'dev-1');
  return (c, port);
}

Widget _wrap(SessionController c, RingAppLauncher l) => MaterialApp(
      home: CaptionsOnlyScreen(controller: c, launcher: l),
    );

void main() {
  group('The banner is the shared StatusBanner (audit section 3.6)', () {
    testWidgets('it renders as a StatusBanner in the warning variant',
        (tester) async {
      final (c, port) = await _captionsOnly();
      await tester.pumpWidget(_wrap(c, FakeRingAppLauncher()));
      await tester.pump();
      final banner = tester.widget<StatusBanner>(
        find.byKey(const ValueKey('captions-only-banner')),
      );
      // Warning, not danger: Captions-Only is a first-class mode, not an error
      // state (FR-12.4).
      expect(banner.variant, StatusVariant.warning);
      expect(banner.variant, isNot(StatusVariant.danger));
      c.dispose();
      await port.dispose();
    });

    testWidgets('the exact FR-12.2 copy is unchanged', (tester) async {
      final (c, port) = await _captionsOnly();
      await tester.pumpWidget(_wrap(c, FakeRingAppLauncher()));
      await tester.pump();
      final banner = tester.widget<StatusBanner>(
        find.byKey(const ValueKey('captions-only-banner')),
      );
      expect(banner.message, kCaptionsOnlyBanner);
      expect(
        find.text(
          'Replies unavailable on this device. You can still see what your visitor says.',
        ),
        findsOneWidget,
      );
      c.dispose();
      await port.dispose();
    });

    testWidgets('it carries an icon, which the old banner did not',
        (tester) async {
      final (c, port) = await _captionsOnly();
      await tester.pumpWidget(_wrap(c, FakeRingAppLauncher()));
      await tester.pump();
      expect(find.byIcon(Icons.mic_off_outlined), findsOneWidget);
      c.dispose();
      await port.dispose();
    });

    testWidgets('the banner fill is opaque so it is legible over video',
        (tester) async {
      final (c, port) = await _captionsOnly();
      await tester.pumpWidget(_wrap(c, FakeRingAppLauncher()));
      await tester.pump();
      final context = tester.element(find.byType(StatusBanner));
      expect(StatusBanner.backgroundFor(context, StatusVariant.warning).a, 1.0);
      c.dispose();
      await port.dispose();
    });
  });

  group('Open Ring app got weight and an icon (audit section 5, FR-12.3)', () {
    testWidgets('it is a filled button with an open-in-new icon',
        (tester) async {
      final (c, port) = await _captionsOnly();
      await tester.pumpWidget(_wrap(c, FakeRingAppLauncher()));
      await tester.pump();
      expect(
        find.byWidgetPredicate((w) => w is FilledButton),
        findsWidgets,
        reason:
            'the action was an OutlinedButton with hand-painted white borders',
      );
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
      expect(find.text('Open Ring app'), findsOneWidget);
      c.dispose();
      await port.dispose();
    });

    testWidgets('it still launches the Ring app in one tap', (tester) async {
      final (c, port) = await _captionsOnly();
      final launcher = FakeRingAppLauncher();
      await tester.pumpWidget(_wrap(c, launcher));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('open-ring-app')));
      await tester.pump();
      expect(launcher.launchCalls, 1);
      c.dispose();
      await port.dispose();
    });

    testWidgets('it meets the 48dp minimum target', (tester) async {
      final (c, port) = await _captionsOnly();
      await tester.pumpWidget(_wrap(c, FakeRingAppLauncher()));
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const ValueKey('open-ring-app'))).height,
        greaterThanOrEqualTo(TouchTarget.minimum),
      );
      c.dispose();
      await port.dispose();
    });
  });

  group('Colors come from the system (audit C2)', () {
    testWidgets('the scaffold uses the captionSurface role', (tester) async {
      final (c, port) = await _captionsOnly();
      await tester.pumpWidget(_wrap(c, FakeRingAppLauncher()));
      await tester.pump();
      final context = tester.element(find.byType(Scaffold));
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        ThresholdSemanticColors.of(context).captionSurface,
      );
      c.dispose();
      await port.dispose();
    });

    testWidgets(
        'it shares the media surface theme with the two-way screen (FR-12.4)',
        (tester) async {
      final (c, port) = await _captionsOnly();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: CaptionsOnlyScreen(
              controller: c, launcher: FakeRingAppLauncher()),
        ),
      );
      await tester.pump();
      final context = tester.element(find.byType(Scaffold));
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(Theme.of(context).colorScheme, mediaSurfaceTheme().colorScheme);
      c.dispose();
      await port.dispose();
    });

    testWidgets('the caption region fill is opaque (FR-10.2, NFR-2)',
        (tester) async {
      final (c, port) = await _captionsOnly();
      await tester.pumpWidget(_wrap(c, FakeRingAppLauncher()));
      await tester.pump();
      final container = tester.widget<Container>(
        find.byKey(const ValueKey('captions-only-region')),
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color!.a, 1.0);
      expect(decoration.color, ThresholdSettings.defaults().captionBackground);
      expect(decoration.borderRadius, Radii.roundedLarge);
      c.dispose();
      await port.dispose();
    });
  });

  group('Captions-Only stays receive-only and accessible', () {
    testWidgets(
        'there is still no reply bar and no visitor prompt (FR-12.1, N9)',
        (tester) async {
      final (c, port) = await _captionsOnly();
      await tester.pumpWidget(_wrap(c, FakeRingAppLauncher()));
      await tester.pump();
      expect(find.byKey(const ValueKey('reply-bar')), findsNothing);
      expect(
          find.byKey(const ValueKey('captions-only-region')), findsOneWidget);
      c.dispose();
      await port.dispose();
    });

    testWidgets('every Semantics label survives the refactor (G4, AT-10)',
        (tester) async {
      final handle = tester.ensureSemantics();
      final (c, port) = await _captionsOnly();
      await tester.pumpWidget(_wrap(c, FakeRingAppLauncher()));
      await tester.pump();
      expect(find.bySemanticsLabel('Live video from your doorbell'),
          findsOneWidget);
      expect(
          find.bySemanticsLabel(RegExp('Replies unavailable')), findsOneWidget);
      expect(find.bySemanticsLabel('Open Ring app'), findsOneWidget);
      expect(find.bySemanticsLabel('End session'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Visitor captions')), findsOneWidget);
      handle.dispose();
      c.dispose();
      await port.dispose();
    });

    testWidgets('overlays stay clear of the watermark corners (FR-4.5)',
        (tester) async {
      final (c, port) = await _captionsOnly();
      await tester.pumpWidget(_wrap(c, FakeRingAppLauncher()));
      await tester.pump();
      for (final key in <ValueKey<String>>[
        const ValueKey('captions-only-banner'),
        const ValueKey('captions-only-region'),
      ]) {
        final rect = tester.getRect(find.byKey(key));
        expect(rect.top, greaterThanOrEqualTo(kWatermarkBandHeight));
      }
      c.dispose();
      await port.dispose();
    });

    testWidgets('a long conversation scrolls instead of overflowing',
        (tester) async {
      final (c, port) = await _captionsOnly();
      for (var i = 0; i < 14; i++) {
        c.ingestCaption(CaptionResult(
          speaker: CaptionSpeaker.visitor,
          text: 'turn number $i with a reasonable amount of words in it',
          isFinal: true,
          timestampMs: i * 5000,
          segmentBoundary: true,
          confidence: 0.9,
        ));
      }
      await tester.pumpWidget(_wrap(c, FakeRingAppLauncher()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('caption-turn-13')), findsOneWidget);
      c.dispose();
      await port.dispose();
    });
  });

  group('Landscape gives captions their own column', () {
    testWidgets('the caption region is taller and takes one side',
        (tester) async {
      final (c, port) = await _captionsOnly();
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_wrap(c, FakeRingAppLauncher()));
      await tester.pump();
      final portrait =
          tester.getSize(find.byKey(const ValueKey('captions-only-region')));

      tester.view.physicalSize = const Size(800, 400);
      await tester.pumpWidget(_wrap(c, FakeRingAppLauncher()));
      await tester.pump();
      final landscape =
          tester.getRect(find.byKey(const ValueKey('captions-only-region')));
      expect(tester.takeException(), isNull);
      expect(landscape.height, greaterThan(portrait.height));
      expect(landscape.width, lessThan(800 * 0.75));
      // And it still clears the watermark band.
      expect(landscape.top, greaterThanOrEqualTo(kWatermarkBandHeight));
      c.dispose();
      await port.dispose();
    });
  });
}
