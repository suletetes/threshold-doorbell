// Caption surface presentation (UI/UX audit C7: "this is the hero surface of the
// entire product and it is styled like a debug overlay... provisional versus
// confident text deserves a deliberate, legible treatment, not just alpha").
//
// The existing test/session/caption_surface_render_test.dart pins the BEHAVIOR
// that must never move: the emphasis mapping (FR-5.3/5.3a, AT-4), the enforced
// >=4.5:1 foreground (FR-10.2, NFR-2, AT-9), the caption scale, and the 200%
// clamp. This file pins the new EXPRESSION, and re-asserts that the expression
// did not buy itself anything at the behavior's expense.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/captions/caption_surface.dart';
import 'package:threshold/captions/turn_segmentation.dart';
import 'package:threshold/design/colors.dart';
import 'package:threshold/design/theme.dart';
import 'package:threshold/design/typography.dart';
import 'package:threshold/settings/contrast.dart';
import 'package:threshold/settings/settings_state.dart';

CaptionTurn _turn({
  CaptionSpeaker speaker = CaptionSpeaker.visitor,
  String text = 'hello there',
  bool isFinal = true,
  double? confidence = 0.9,
}) =>
    CaptionTurn(
      speaker: speaker,
      text: text,
      isFinal: isFinal,
      startedAtMs: 0,
      lastUpdatedMs: 0,
      confidence: isFinal ? confidence : null,
      provisional: !isFinal,
    );

Widget _host(
  List<CaptionTurn> turns, {
  ThresholdSettings? settings,
  bool dark = true,
}) =>
    MaterialApp(
      theme: dark ? ThresholdTheme.dark() : ThresholdTheme.light(),
      home: Scaffold(
        body: CaptionSurface(
          turns: turns,
          settings: settings ?? ThresholdSettings.defaults(),
        ),
      ),
    );

/// Every leaf TextSpan rendered for turn [index].
List<TextSpan> _spans(WidgetTester tester, int index) {
  final text = tester.widget<Text>(
    find.descendant(
      of: find.byKey(ValueKey('caption-turn-$index')),
      matching: find.byType(Text),
    ),
  );
  final out = <TextSpan>[];
  void walk(TextSpan s) {
    if (s.children == null || s.children!.isEmpty) {
      if (s.text != null) out.add(s);
    } else {
      for (final child in s.children!) {
        if (child is TextSpan) walk(child);
      }
    }
  }

  walk(text.textSpan! as TextSpan);
  return out;
}

void main() {
  group('Per-turn speaker attribution (audit C7)', () {
    testWidgets('each turn names its speaker with an icon', (tester) async {
      await tester.pumpWidget(
        _host(<CaptionTurn>[
          _turn(speaker: CaptionSpeaker.visitor, text: 'is anyone home'),
          _turn(speaker: CaptionSpeaker.resident, text: 'coming now'),
        ]),
      );
      expect(find.byKey(const ValueKey('caption-speaker-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('caption-speaker-1')), findsOneWidget);
      expect(find.text('Visitor'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.byIcon(CaptionSurface.speakerIcon(CaptionSpeaker.visitor)),
          findsOneWidget);
      expect(find.byIcon(CaptionSurface.speakerIcon(CaptionSpeaker.resident)),
          findsOneWidget);
    });

    testWidgets('both speakers have a distinct label and icon', (tester) async {
      final labels =
          CaptionSpeaker.values.map(CaptionSurface.speakerLabel).toSet();
      final icons =
          CaptionSpeaker.values.map(CaptionSurface.speakerIcon).toSet();
      expect(labels.length, CaptionSpeaker.values.length);
      expect(icons.length, CaptionSpeaker.values.length);
    });

    testWidgets('attribution sits above its caption text', (tester) async {
      await tester.pumpWidget(_host(<CaptionTurn>[_turn()]));
      final speakerTop =
          tester.getTopLeft(find.byKey(const ValueKey('caption-speaker-0'))).dy;
      final textTop =
          tester.getTopLeft(find.byKey(const ValueKey('caption-turn-0'))).dy;
      expect(speakerTop, lessThan(textTop));
    });

    testWidgets(
        'attribution does not add a second Text inside the caption node',
        (tester) async {
      // The caption text node stays exactly one Text per turn: the emphasis
      // assertions in AT-4 read that node directly.
      await tester
          .pumpWidget(_host(<CaptionTurn>[_turn(), _turn(text: 'second')]));
      for (var i = 0; i < 2; i++) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('caption-turn-$i')),
            matching: find.byType(Text),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('attribution copy is dash-free (NFR-10)', (tester) async {
      for (final speaker in CaptionSpeaker.values) {
        final label = CaptionSurface.speakerLabel(speaker);
        expect(label.contains('\u2014'), isFalse);
        expect(label.contains('\u2013'), isFalse);
      }
      expect(kProvisionalTurnMarker.contains('\u2014'), isFalse);
      expect(kProvisionalTurnMarker.contains('\u2013'), isFalse);
    });
  });

  group('Provisional treatment is more than alpha (audit C7)', () {
    testWidgets('an unfinalized turn carries the explicit provisional marker',
        (tester) async {
      await tester.pumpWidget(
        _host(<CaptionTurn>[_turn(isFinal: false, text: 'hello the')]),
      );
      expect(find.byKey(const ValueKey('caption-provisional-marker')),
          findsOneWidget);
      expect(find.text(kProvisionalTurnMarker), findsOneWidget);
    });

    testWidgets('a finalized turn carries no provisional marker',
        (tester) async {
      await tester.pumpWidget(
          _host(<CaptionTurn>[_turn(isFinal: true, confidence: 0.9)]));
      expect(find.byKey(const ValueKey('caption-provisional-marker')),
          findsNothing);
    });

    testWidgets(
        'provisional text gets a dotted underline on top of the alpha and italic',
        (tester) async {
      await tester.pumpWidget(
          _host(<CaptionTurn>[_turn(isFinal: false, text: 'hello the')]));
      final spans = _spans(tester, 0);
      expect(spans, isNotEmpty);
      for (final span in spans) {
        // The load-bearing emphasis (FR-5.3, AT-4) is untouched.
        expect(span.style?.fontStyle, FontStyle.italic);
        expect(span.style!.color!.a, lessThan(1.0));
        // And the deliberate treatment the audit asked for is added on top.
        expect(span.style?.decoration, TextDecoration.underline);
        expect(span.style?.decorationStyle, TextDecorationStyle.dotted);
      }
    });

    testWidgets(
        'a low-confidence finalized turn is de-emphasized but NOT marked provisional',
        (tester) async {
      // FR-5.3a and FR-5.3 are different states and must stay distinguishable.
      await tester.pumpWidget(_host(<CaptionTurn>[_turn(confidence: 0.4)]));
      final spans = _spans(tester, 0);
      expect(spans.every((s) => s.style!.color!.a < 1.0), isTrue);
      expect(spans.every((s) => s.style?.decoration == null), isTrue);
      expect(find.byKey(const ValueKey('caption-provisional-marker')),
          findsNothing);
    });
  });

  group('Caption chrome goes through the contrast floor (FR-10.2, NFR-2)', () {
    testWidgets('attribution clears 4.5:1 even on a hostile caption background',
        (tester) async {
      // A resident picks a light caption background. The caption roles are dark
      // by design, so an unenforced role color would vanish here.
      final hostile = ThresholdSettings.defaults().copyWith(
        captionForeground: const Color(0xFF111111),
        captionBackground: const Color(0xFFFFFFFF),
      );
      await tester.pumpWidget(_host(<CaptionTurn>[_turn()], settings: hostile));
      final attribution = tester.widget<Text>(find.text('Visitor'));
      expect(
        meetsContrastFloor(
            attribution.style!.color!, hostile.captionBackground),
        isTrue,
        reason: 'the speaker label must be legible on any chosen background',
      );
    });

    testWidgets('the provisional marker clears 4.5:1 on a hostile background',
        (tester) async {
      final hostile = ThresholdSettings.defaults().copyWith(
        captionForeground: const Color(0xFF111111),
        captionBackground: const Color(0xFFFFFFFF),
      );
      await tester.pumpWidget(
        _host(<CaptionTurn>[_turn(isFinal: false)], settings: hostile),
      );
      final marker = tester.widget<Text>(find.text(kProvisionalTurnMarker));
      expect(
        meetsContrastFloor(marker.style!.color!, hostile.captionBackground),
        isTrue,
      );
    });

    testWidgets(
        'on the designed dark background the roles pass through unchanged',
        (tester) async {
      // Enforcement only intervenes when a role would fail, so the designed
      // pairing keeps the designed color.
      await tester.pumpWidget(_host(<CaptionTurn>[_turn()]));
      final context = tester.element(find.byType(CaptionSurface));
      final semantic = ThresholdSemanticColors.of(context);
      final defaults = ThresholdSettings.defaults();
      expect(
        tester.widget<Text>(find.text('Visitor')).style?.color,
        enforceContrastFloor(
            semantic.captionOnSurface, defaults.captionBackground),
      );
    });
  });

  group('Caption metrics come from the type scale (audit C3)', () {
    testWidgets(
        'the base caption size is the largest title role, not a raw number',
        (tester) async {
      expect(
          kBaseCaptionFontSize, ThresholdTypography.base.titleLarge!.fontSize);
      expect(kCaptionLineHeight, ThresholdTypography.base.titleLarge!.height);
    });

    testWidgets(
        'the caption text still scales with the resident caption scale (FR-10.2)',
        (tester) async {
      final big = ThresholdSettings.defaults().copyWith(captionScale: 2.0);
      await tester.pumpWidget(_host(<CaptionTurn>[_turn()], settings: big));
      final text = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('caption-turn-0')),
          matching: find.byType(Text),
        ),
      );
      expect(text.style?.fontSize, kBaseCaptionFontSize * 2.0);
      expect(text.style?.height, kCaptionLineHeight);
    });
  });

  group('Caption empty state (audit section 4, feedback states)', () {
    testWidgets('renders an icon and the placeholder copy, keyed as before',
        (tester) async {
      await tester.pumpWidget(_host(const <CaptionTurn>[]));
      expect(find.byKey(const ValueKey('caption-empty')), findsOneWidget);
      expect(find.text('Captions appear here as your visitor speaks.'),
          findsOneWidget);
      expect(find.byIcon(Icons.closed_caption_off_outlined), findsOneWidget);
    });

    testWidgets('the empty state uses the enforced caption foreground',
        (tester) async {
      final hostile = ThresholdSettings.defaults().copyWith(
        captionForeground: const Color(0xFF050505),
        captionBackground: const Color(0xFF000000),
      );
      await tester.pumpWidget(_host(const <CaptionTurn>[], settings: hostile));
      final title =
          tester.widget<Text>(find.byKey(const ValueKey('caption-empty')));
      expect(title.style?.color, hostile.captionForeground);
      expect(meetsContrastFloor(title.style!.color!, hostile.captionBackground),
          isTrue);
    });

    testWidgets('the empty state disappears as soon as a turn arrives',
        (tester) async {
      await tester.pumpWidget(_host(<CaptionTurn>[_turn()]));
      expect(find.byKey(const ValueKey('caption-empty')), findsNothing);
    });
  });

  group('The 200% clamp survives the redesign (NFR-2)', () {
    testWidgets('a hostile OS scale is clamped on the caption subtree',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThresholdTheme.dark(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(4.0)),
            child: Scaffold(
              body: CaptionSurface(
                turns: <CaptionTurn>[_turn()],
                settings: ThresholdSettings.defaults(),
              ),
            ),
          ),
        ),
      );
      final mq = tester.widget<MediaQuery>(
        find
            .descendant(
                of: find.byType(CaptionSurface),
                matching: find.byType(MediaQuery))
            .first,
      );
      expect(mq.data.textScaler.scale(10),
          lessThanOrEqualTo(10 * kMaxCaptionTextScale));
    });
  });
}
