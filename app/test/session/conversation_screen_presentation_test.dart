// Conversation screen presentation (UI/UX audit C1, C2, C4, C6 and section 4,
// "Responsive and adaptive"). The pre-existing conversation_screen_test.dart
// pins the state machine wiring; this file pins the presentation decisions that
// replaced the audit's findings, and the recovery path that C4 called "the single
// worst UX defect found".

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/captions/caption_surface.dart';
import 'package:threshold/captions/turn_segmentation.dart';
import 'package:threshold/design/colors.dart';
import 'package:threshold/design/components/components.dart';
import 'package:threshold/design/tokens.dart';
import 'package:threshold/session/conversation_screen.dart';
import 'package:threshold/session/session_controller.dart';
import 'package:threshold/session/session_port.dart';
import 'package:threshold/session/session_state.dart';
import 'package:threshold/session/watermark_safe_area.dart';
import 'package:threshold/settings/settings_state.dart';

Widget _wrap(
  SessionController c, {
  bool disableAnimations = false,
  ThresholdSettings? settings,
}) =>
    MaterialApp(
      home: Builder(
        // copyWith, not a fresh MediaQueryData: a fresh one would zero out the
        // surface size and make every orientation look like portrait.
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: disableAnimations),
          child: ConversationScreen(controller: c, settings: settings),
        ),
      ),
    );

Future<(SessionController, FakeSessionPort)> _live(
    {bool privacy = false}) async {
  final port = FakeSessionPort();
  final c = SessionController(port: port);
  await c.open(
    deviceId: 'dev-1',
    mode: privacy ? SessionCaptionMode.privacy : SessionCaptionMode.clarity,
  );
  return (c, port);
}

Future<(SessionController, FakeSessionPort)> _failed() async {
  final port = FakeSessionPort(
    connectPlan: <ConnectPlan>[ConnectPlan.fail, ConnectPlan.fail],
  );
  final c = SessionController(port: port);
  await c.open(deviceId: 'dev-1');
  return (c, port);
}

void main() {
  group('The error state offers a way forward (audit C4)', () {
    testWidgets('it has an icon, the failure, and a plain-language cause',
        (tester) async {
      final (c, port) = await _failed();
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      expect(find.byKey(const ValueKey('status-error')), findsOneWidget);
      // The exact controller message is still shown verbatim (FR-4.4).
      expect(find.text("Couldn't connect to your doorbell."), findsOneWidget);
      // What the audit found missing.
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      expect(find.text(kConnectionFailureCause), findsOneWidget);
      c.dispose();
      await port.dispose();
    });

    testWidgets('Try again re-runs the controller open path and reaches live',
        (tester) async {
      final (c, port) = await _failed();
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      final attemptsBefore = port.connectCalls;
      await tester.tap(find.byKey(const ValueKey('error-retry')));
      await tester.pumpAndSettle();
      expect(port.connectCalls, greaterThan(attemptsBefore));
      expect(c.state, SessionState.live);
      expect(find.byKey(const ValueKey('status-error')), findsNothing);
      expect(find.byKey(const ValueKey('caption-region')), findsOneWidget);
      c.dispose();
      await port.dispose();
    });

    testWidgets(
        'Try again that fails again returns to the error state, not a crash',
        (tester) async {
      final port = FakeSessionPort(
        connectPlan: <ConnectPlan>[
          ConnectPlan.fail,
          ConnectPlan.fail,
          ConnectPlan.fail,
          ConnectPlan.fail,
        ],
      );
      final c = SessionController(port: port);
      await c.open(deviceId: 'dev-1');
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('error-retry')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(c.state, SessionState.error);
      // Still offering a way forward rather than becoming a dead end.
      expect(find.byKey(const ValueKey('error-retry')), findsOneWidget);
      c.dispose();
      await port.dispose();
    });

    testWidgets('Go back is a secondary escape that tears the session down',
        (tester) async {
      final (c, port) = await _failed();
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      expect(find.byKey(const ValueKey('error-go-back')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('error-go-back')));
      await tester.pumpAndSettle();
      expect(port.closeCalls, 1);
      c.dispose();
      await port.dispose();
    });

    testWidgets('both recovery actions meet the 48dp minimum target',
        (tester) async {
      final (c, port) = await _failed();
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      for (final key in <ValueKey<String>>[
        const ValueKey('error-retry'),
        const ValueKey('error-go-back'),
      ]) {
        expect(
          tester.getSize(find.byKey(key)).height,
          greaterThanOrEqualTo(TouchTarget.minimum),
          reason: '$key must be at least 48dp tall',
        );
      }
      c.dispose();
      await port.dispose();
    });

    testWidgets(
        'the failure and its cause are announced together, plus two buttons (G4)',
        (tester) async {
      final handle = tester.ensureSemantics();
      final (c, port) = await _failed();
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      expect(
        find.bySemanticsLabel(
          "Couldn't connect to your doorbell. $kConnectionFailureCause",
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Try again'), findsOneWidget);
      expect(find.bySemanticsLabel('Go back'), findsOneWidget);
      handle.dispose();
      c.dispose();
      await port.dispose();
    });

    testWidgets('the cause copy is dash-free (NFR-10)', (tester) async {
      expect(kConnectionFailureCause.contains('\u2014'), isFalse);
      expect(kConnectionFailureCause.contains('\u2013'), isFalse);
    });
  });

  group('State changes are visible (audit C6: zero motion)', () {
    testWidgets(
        'state panels are wrapped in an AnimatedSwitcher on a motion token',
        (tester) async {
      final (c, port) = await _live();
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      final switcher =
          tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
      expect(switcher.duration, Motion.emphasized);
      expect(switcher.switchInCurve, Motion.enterCurve);
      expect(switcher.switchOutCurve, Motion.exitCurve);
      c.dispose();
      await port.dispose();
    });

    testWidgets('reduced motion collapses the transition to zero',
        (tester) async {
      final (c, port) = await _live();
      await tester.pumpWidget(_wrap(c, disableAnimations: true));
      await tester.pump();
      expect(
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
        Motion.instant,
      );
      c.dispose();
      await port.dispose();
    });

    testWidgets('a state change swaps the panel and settles', (tester) async {
      final (c, port) = await _live();
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      expect(find.byKey(const ValueKey('caption-region')), findsOneWidget);
      c.onBackgrounded();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('status-backgrounded')), findsOneWidget);
      c.dispose();
      await port.dispose();
    });

    testWidgets('a caption update does not restart the live transition',
        (tester) async {
      final (c, port) = await _live();
      await tester.pumpWidget(_wrap(c));
      await tester.pumpAndSettle();
      c.ingestCaption(const CaptionResult(
        speaker: CaptionSpeaker.visitor,
        text: 'is anyone home',
        isFinal: true,
        timestampMs: 0,
        confidence: 0.9,
      ));
      await tester.pump();
      // The live overlay keeps a stable key, so the switcher treats this as an
      // update rather than a new child: the captions are visible immediately.
      expect(find.byKey(const ValueKey('caption-turn-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('overlay-live')), findsOneWidget);
      c.dispose();
      await port.dispose();
    });
  });

  group('Nothing moves at all under reduced motion (audit principle 3)', () {
    testWidgets('the connecting spinner becomes a static marker',
        (tester) async {
      // Gate connect so we are deterministically in the connecting state while
      // we assert, instead of racing the fake to live.
      final gate = Completer<void>();
      final port = FakeSessionPort(connectGate: gate.future);
      final c = SessionController(port: port);
      final opening = c.open(deviceId: 'dev-1');
      await tester.pumpWidget(_wrap(c, disableAnimations: true));
      await tester.pump();
      // The connecting panel is actually on screen...
      expect(c.state, SessionState.connecting);
      expect(find.byKey(const ValueKey('status-connecting')), findsOneWidget);
      // ...and a spinning CircularProgressIndicator is the one animation Flutter
      // does not stop on its own, so under reduced motion the panel substitutes
      // a static marker. Reverting that substitution fails this assertion.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      gate.complete();
      await opening;
      await tester.pumpAndSettle();
      c.dispose();
      await port.dispose();
    });

    testWidgets('the paused panel still shows its own state icon',
        (tester) async {
      final (c, port) = await _live();
      c.onBackgrounded();
      await tester.pumpWidget(_wrap(c, disableAnimations: true));
      await tester.pump();
      expect(find.byKey(const ValueKey('status-backgrounded')), findsOneWidget);
      expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      c.dispose();
      await port.dispose();
    });

    testWidgets('the caption skeleton lands on its resting value immediately',
        (tester) async {
      final port = FakeSessionPort();
      final c = SessionController(port: port);
      final opening = c.open(deviceId: 'dev-1');
      await tester.pumpWidget(_wrap(c, disableAnimations: true));
      await tester.pump();
      for (final block
          in tester.widgetList<SkeletonBlock>(find.byType(SkeletonBlock))) {
        expect(block.height, Spacing.space4);
      }
      expect(tester.takeException(), isNull);
      await opening;
      await tester.pumpAndSettle();
      c.dispose();
      await port.dispose();
    });
  });

  group('Connecting states preview the caption region (perceived performance)',
      () {
    testWidgets('the connecting panel shows skeleton lines', (tester) async {
      // Gate connect so the connecting panel is deterministically present; the
      // old version guarded the assertion behind an if, so it passed even when
      // no skeleton ever rendered.
      final gate = Completer<void>();
      final port = FakeSessionPort(connectGate: gate.future);
      final c = SessionController(port: port);
      final opening = c.open(deviceId: 'dev-1');
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      expect(c.state, SessionState.connecting);
      expect(
        find.byType(SkeletonBlock),
        findsNWidgets(3),
        reason: 'three uneven caption lines, not a progress meter',
      );
      gate.complete();
      await opening;
      await tester.pumpAndSettle();
      // Gone once captions can actually arrive.
      expect(find.byType(SkeletonBlock), findsNothing);
      c.dispose();
      await port.dispose();
    });
  });

  group('The mode badge is the shared Pill (audit C2, component consistency)',
      () {
    testWidgets('it renders a Pill in the live semantic role', (tester) async {
      final (c, port) = await _live();
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      final pill =
          tester.widget<Pill>(find.byKey(const ValueKey('mode-badge')));
      // Read the theme from inside the screen: the media surface pins its own.
      final context = tester.element(find.byType(Scaffold));
      expect(pill, isA<Pill>());
      expect(pill.color, ThresholdSemanticColors.of(context).live);
      c.dispose();
      await port.dispose();
    });

    testWidgets('each mode gets its own icon and label', (tester) async {
      final (clarity, clarityPort) = await _live();
      await tester.pumpWidget(_wrap(clarity));
      await tester.pump();
      expect(find.text('Clarity Mode'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
      clarity.dispose();
      await clarityPort.dispose();

      final (privacy, privacyPort) = await _live(privacy: true);
      await tester.pumpWidget(_wrap(privacy));
      await tester.pump();
      expect(find.text('Privacy Mode'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      privacy.dispose();
      await privacyPort.dispose();
    });

    testWidgets('it keeps its Semantics label (G4)', (tester) async {
      final handle = tester.ensureSemantics();
      final (c, port) = await _live();
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      expect(
        find.bySemanticsLabel('Active caption mode: Clarity Mode'),
        findsOneWidget,
      );
      handle.dispose();
      c.dispose();
      await port.dispose();
    });

    testWidgets('it stays clear of the watermark corners (FR-4.5)',
        (tester) async {
      final (c, port) = await _live();
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      final badge = tester.getRect(find.byKey(const ValueKey('mode-badge')));
      expect(badge.top, greaterThanOrEqualTo(kWatermarkBandHeight));
      c.dispose();
      await port.dispose();
    });
  });

  group('Colors come from the system (audit C1, C2)', () {
    testWidgets('the scaffold uses the captionSurface role, not a literal',
        (tester) async {
      final (c, port) = await _live();
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      final context = tester.element(find.byType(Scaffold));
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor,
          ThresholdSemanticColors.of(context).captionSurface);
      c.dispose();
      await port.dispose();
    });

    testWidgets(
        'the media surface pins the dark scheme rather than following the platform',
        (tester) async {
      final (c, port) = await _live();
      await tester.pumpWidget(
        MaterialApp(
          // A light platform theme: the video surface must stay dark anyway.
          theme: ThemeData.light(),
          home: ConversationScreen(controller: c),
        ),
      );
      await tester.pump();
      final context = tester.element(find.byType(Scaffold));
      expect(Theme.of(context).brightness, Brightness.dark);
      c.dispose();
      await port.dispose();
    });

    testWidgets(
        'the auth recovery scrim is the theme scrim (replaces 0xB3000000)',
        (tester) async {
      final (c, port) = await _live();
      c.beginAuthRecovery();
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      expect(
          find.byKey(const ValueKey('auth-recovery-prompt')), findsOneWidget);
      final context =
          tester.element(find.byKey(const ValueKey('auth-recovery-prompt')));
      final scrim =
          tester.widgetList<ColoredBox>(find.byType(ColoredBox)).firstWhere(
                (box) => box.color.a > 0 && box.color.a < 1,
              );
      expect(scrim.color.r, Theme.of(context).colorScheme.scrim.r);
      expect(scrim.color.g, Theme.of(context).colorScheme.scrim.g);
      expect(scrim.color.b, Theme.of(context).colorScheme.scrim.b);
      expect(scrim.color.a, closeTo(kModalScrimOpacity, 1e-3));
      c.dispose();
      await port.dispose();
    });
  });

  group('The caption container strengthens the contrast floor (FR-10.2, NFR-2)',
      () {
    testWidgets('the fill is opaque, so video no longer bleeds through it',
        (tester) async {
      final (c, port) = await _live();
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      final container = tester
          .widget<Container>(find.byKey(const ValueKey('caption-region')));
      final decoration = container.decoration! as BoxDecoration;
      expect(
        decoration.color!.a,
        1.0,
        reason:
            'the 4.5:1 floor is computed against the caption background, so '
            'the surface has to actually paint it',
      );
      c.dispose();
      await port.dispose();
    });

    testWidgets('an opaque caption background is painted exactly as chosen',
        (tester) async {
      final (c, port) = await _live();
      final settings = ThresholdSettings.defaults();
      await tester.pumpWidget(_wrap(c, settings: settings));
      await tester.pump();
      final container = tester
          .widget<Container>(find.byKey(const ValueKey('caption-region')));
      expect((container.decoration! as BoxDecoration).color,
          settings.captionBackground);
      c.dispose();
      await port.dispose();
    });

    testWidgets('the region uses a radius token and keeps its live region (G4)',
        (tester) async {
      final handle = tester.ensureSemantics();
      final (c, port) = await _live();
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      final container = tester
          .widget<Container>(find.byKey(const ValueKey('caption-region')));
      expect((container.decoration! as BoxDecoration).borderRadius,
          Radii.roundedLarge);
      expect(find.bySemanticsLabel(RegExp('Visitor captions')), findsOneWidget);
      handle.dispose();
      c.dispose();
      await port.dispose();
    });
  });

  group('Landscape keeps captions readable (audit section 4, responsive)', () {
    Future<void> setSurface(WidgetTester tester, Size size) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
    }

    testWidgets('captions get a full height column instead of a squeezed strip',
        (tester) async {
      final (c, port) = await _live();
      // Portrait first, for the comparison.
      await setSurface(tester, const Size(400, 800));
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      final portraitHeight =
          tester.getSize(find.byKey(const ValueKey('caption-region'))).height;

      // Now landscape on the same device.
      await setSurface(tester, const Size(800, 400));
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      final landscape =
          tester.getRect(find.byKey(const ValueKey('caption-region')));
      expect(tester.takeException(), isNull);
      expect(
        landscape.height,
        greaterThan(portraitHeight),
        reason: 'landscape is the orientation someone props a phone in to read',
      );
      // And it occupies one side rather than a full width band.
      expect(landscape.width, lessThan(800 * 0.75));
      c.dispose();
      await port.dispose();
    });

    testWidgets('the landscape caption column scrolls instead of overflowing',
        (tester) async {
      final (c, port) = await _live();
      for (var i = 0; i < 12; i++) {
        c.ingestCaption(CaptionResult(
          speaker: CaptionSpeaker.visitor,
          text: 'turn number $i with a reasonable amount of words in it',
          isFinal: true,
          timestampMs: i * 5000,
          segmentBoundary: true,
          confidence: 0.9,
        ));
      }
      await setSurface(tester, const Size(800, 400));
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('caption-region')),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      // Every turn is still in the tree, newest anchored into view.
      expect(find.byKey(const ValueKey('caption-turn-11')), findsOneWidget);
      c.dispose();
      await port.dispose();
    });

    testWidgets('landscape still clears the watermark band (FR-4.5)',
        (tester) async {
      final (c, port) = await _live();
      await setSurface(tester, const Size(800, 400));
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      final region =
          tester.getRect(find.byKey(const ValueKey('caption-region')));
      expect(region.top, greaterThanOrEqualTo(kWatermarkBandHeight));
      expect(clearsWatermarkCorners(region, const Size(800, 400)), isTrue);
      c.dispose();
      await port.dispose();
    });

    testWidgets('the end control stays reachable and 48dp in landscape',
        (tester) async {
      final (c, port) = await _live();
      await setSurface(tester, const Size(800, 400));
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      final size = tester.getSize(find.byKey(const ValueKey('end-session')));
      expect(size.height, greaterThanOrEqualTo(TouchTarget.minimum));
      await tester.tap(find.byKey(const ValueKey('end-session')));
      await tester.pumpAndSettle();
      expect(port.closeCalls, 1);
      c.dispose();
      await port.dispose();
    });
  });

  group('The end control gained an icon (audit section 4, iconography)', () {
    testWidgets('it shows an end-call icon and keeps its label and key',
        (tester) async {
      final (c, port) = await _live();
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      expect(find.byKey(const ValueKey('end-session')), findsOneWidget);
      expect(find.byIcon(Icons.call_end_rounded), findsOneWidget);
      expect(find.text('End call'), findsOneWidget);
      c.dispose();
      await port.dispose();
    });
  });

  group('Caption surface still renders inside the region', () {
    testWidgets('the caption subtree lives under the keyed region',
        (tester) async {
      final (c, port) = await _live();
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('caption-region')),
          matching: find.byType(CaptionSurface),
        ),
        findsOneWidget,
      );
      c.dispose();
      await port.dispose();
    });
  });
}
