// P1-2: the live caption surface renders real caption turns/tokens with the
// tested confidence emphasis and the enforced accessibility settings, on the
// ACTUAL screens (not just the pure functions). Covers FR-5.3/5.3a (AT-4),
// FR-10.2/NFR-2 contrast floor (AT-9), and the caption text scale.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/captions/caption_surface.dart';
import 'package:threshold/captions/turn_segmentation.dart';
import 'package:threshold/session/captions_only_screen.dart';
import 'package:threshold/session/conversation_screen.dart';
import 'package:threshold/session/ring_app_launcher.dart';
import 'package:threshold/session/session_controller.dart';
import 'package:threshold/session/session_port.dart';
import 'package:threshold/settings/contrast.dart';
import 'package:threshold/settings/settings_state.dart';

Future<SessionController> _liveController({bool captionsOnly = false}) async {
  final port = FakeSessionPort(probeSucceeds: !captionsOnly);
  final c = SessionController(port: port);
  await c.open(deviceId: 'dev-1');
  return c;
}

/// Feed a partial then a low-confidence final then a high-confidence final,
/// each as its own labeled turn (segment boundary forces new turns).
void _seedMixedTurns(SessionController c) {
  c.ingestCaption(const CaptionResult(
    speaker: CaptionSpeaker.visitor,
    text: 'hello there',
    isFinal: false,
    timestampMs: 0,
  ));
  c.ingestCaption(const CaptionResult(
    speaker: CaptionSpeaker.visitor,
    text: 'low one',
    isFinal: true,
    timestampMs: 100,
    segmentBoundary: true,
    confidence: 0.4, // < 0.6 -> de-emphasized (FR-5.3a)
  ));
  c.ingestCaption(const CaptionResult(
    speaker: CaptionSpeaker.visitor,
    text: 'clear words',
    isFinal: true,
    timestampMs: 200,
    segmentBoundary: true,
    confidence: 0.9, // >= 0.6 -> normal (FR-5.3a)
  ));
}

/// Collect every rendered TextSpan (leaf) under [finder].
List<TextSpan> _leafSpans(WidgetTester tester, Finder finder) {
  final texts = tester.widgetList<Text>(find.descendant(of: finder, matching: find.byType(Text)));
  final out = <TextSpan>[];
  for (final t in texts) {
    final span = t.textSpan;
    if (span is! TextSpan) continue;
    void walk(TextSpan s) {
      if (s.children == null || s.children!.isEmpty) {
        if (s.text != null) out.add(s);
      } else {
        for (final child in s.children!) {
          if (child is TextSpan) walk(child);
        }
      }
    }
    walk(span);
  }
  return out;
}

void main() {
  group('Caption surface renders emphasis on the real screen (AT-4, P1-2)', () {
    testWidgets('provisional and low-confidence tokens are de-emphasized; >=0.6 normal', (tester) async {
      final c = await _liveController();
      _seedMixedTurns(c);
      await tester.pumpWidget(MaterialApp(home: ConversationScreen(controller: c)));
      await tester.pump();

      final region = find.byKey(const ValueKey('caption-region'));
      // Provisional turn: italic + reduced alpha.
      final provisional = _leafSpans(tester, find.byKey(const ValueKey('caption-turn-0')));
      expect(provisional, isNotEmpty);
      expect(provisional.every((s) => s.style?.fontStyle == FontStyle.italic), isTrue);
      expect(provisional.every((s) => (s.style!.color!.a) < 1.0), isTrue);

      // Low-confidence final (<0.6): de-emphasized (reduced alpha, w400).
      final low = _leafSpans(tester, find.byKey(const ValueKey('caption-turn-1')));
      expect(low, isNotEmpty);
      expect(low.every((s) => (s.style!.color!.a) < 1.0), isTrue);
      expect(low.every((s) => s.style?.fontWeight == FontWeight.w400), isTrue);

      // High-confidence final (>=0.6): normal (full alpha, bold).
      final normal = _leafSpans(tester, find.byKey(const ValueKey('caption-turn-2')));
      expect(normal, isNotEmpty);
      expect(normal.every((s) => (s.style!.color!.a) >= 1.0 - 1e-9), isTrue);
      expect(normal.every((s) => s.style?.fontWeight == FontWeight.w600), isTrue);

      expect(region, findsOneWidget);
      c.dispose();
    });

    testWidgets('0.6 confidence is inclusive normal (boundary, FR-5.3a)', (tester) async {
      final c = await _liveController();
      c.ingestCaption(const CaptionResult(
        speaker: CaptionSpeaker.visitor,
        text: 'edge case',
        isFinal: true,
        timestampMs: 0,
        confidence: 0.6,
      ));
      await tester.pumpWidget(MaterialApp(home: ConversationScreen(controller: c)));
      await tester.pump();
      final spans = _leafSpans(tester, find.byKey(const ValueKey('caption-turn-0')));
      expect(spans, isNotEmpty);
      expect(spans.every((s) => s.style?.fontWeight == FontWeight.w600), isTrue);
      c.dispose();
    });
  });

  group('Caption surface enforces the contrast floor (AT-9, P1-2)', () {
    testWidgets('a low-contrast user setting still renders a >=4.5:1 foreground', (tester) async {
      final c = await _liveController();
      _seedMixedTurns(c);
      // A user picks a near-black foreground on a near-black background: the
      // ThresholdSettings constructor enforces the floor, and the surface uses
      // that enforced foreground.
      final lowContrast = ThresholdSettings.defaults().copyWith(
        captionForeground: const Color(0xFF050505),
        captionBackground: const Color(0xFF000000),
      );
      await tester.pumpWidget(MaterialApp(
        home: ConversationScreen(controller: c, settings: lowContrast),
      ));
      await tester.pump();
      // The rendered normal-token color meets the floor against the background.
      final normal = _leafSpans(tester, find.byKey(const ValueKey('caption-turn-2')));
      expect(normal, isNotEmpty);
      final fg = normal.first.style!.color!;
      expect(
        meetsContrastFloor(fg, lowContrast.captionBackground),
        isTrue,
        reason: 'caption foreground must meet 4.5:1 even for a low-contrast setting',
      );
      c.dispose();
    });
  });

  group('Caption surface honors the caption scale (FR-10.2, P1-2)', () {
    testWidgets('a larger caption scale increases the caption font size', (tester) async {
      final c = await _liveController();
      _seedMixedTurns(c);
      final big = ThresholdSettings.defaults().copyWith(captionScale: 2.0);
      await tester.pumpWidget(MaterialApp(
        home: ConversationScreen(controller: c, settings: big),
      ));
      await tester.pump();
      final t = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('caption-turn-2')),
          matching: find.byType(Text),
        ),
      );
      expect(t.style?.fontSize, kBaseCaptionFontSize * 2.0);
      c.dispose();
    });

    testWidgets('captions-only screen also renders real turns (P1-2)', (tester) async {
      final c = await _liveController(captionsOnly: true);
      _seedMixedTurns(c);
      await tester.pumpWidget(MaterialApp(
        home: CaptionsOnlyScreen(controller: c, launcher: FakeRingAppLauncher()),
      ));
      await tester.pump();
      // The hardcoded placeholder is gone; real turns render.
      expect(find.text('Captions appear here as your visitor speaks.'), findsNothing);
      expect(find.byKey(const ValueKey('caption-turn-2')), findsOneWidget);
      c.dispose();
    });

    testWidgets('OS text scaling is clamped to 200% on the caption subtree (NFR-2)', (tester) async {
      final c = await _liveController();
      _seedMixedTurns(c);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          // A hostile OS setting far above 200%.
          data: const MediaQueryData(textScaler: TextScaler.linear(4.0)),
          child: ConversationScreen(controller: c),
        ),
      ));
      await tester.pump();
      // Inside the caption surface the effective scaler is clamped to <= 2.0.
      final mq = tester.widget<MediaQuery>(
        find
            .descendant(
              of: find.byKey(const ValueKey('caption-region')),
              matching: find.byType(MediaQuery),
            )
            .first,
      );
      expect(mq.data.textScaler.scale(10) <= 20.0 + 1e-9, isTrue);
      c.dispose();
    });
  });
}
