// Live caption surface (Task 13/17 wiring, FR-5.3, FR-5.3a, FR-10.2, NFR-2;
// AT-4, AT-9). The single widget that renders real caption turns/tokens on both
// the Conversation and Captions-Only screens. It consumes the tested pure logic
// (emphasisForToken / CaptionEmphasis, CaptionTurn / TurnAccumulator) and the
// resident's accessibility settings:
//
//   * a PARTIAL turn renders whole-fragment provisional / de-emphasized (FR-5.3),
//   * a FINALIZED token below 0.6 renders de-emphasized, at or above 0.6 renders
//     normal (FR-5.3a, 0.6 inclusive),
//   * the caption text honors the resident's caption scale (FR-10.2),
//   * the foreground is the enforced >=4.5:1 color from settings so no user
//     contrast setting can breach the floor on the surface where captions
//     actually render (NFR-2, FR-10.2, AT-9),
//   * OS text scaling is clamped to 200% on the caption subtree (NFR-2).
//
// The styling decision lives in caption_styling.dart; this widget only maps the
// emphasis to opacity/weight. No dashes appear in any label (NFR-10).

import 'package:flutter/material.dart';

import '../settings/settings_state.dart';
import 'caption_styling.dart';
import 'turn_segmentation.dart';

/// The base caption font size at scale 1.0. Multiplied by the resident's caption
/// scale (FR-10.2). Kept generous for the dominant caption surface (design §8.2).
const double kBaseCaptionFontSize = 22.0;

/// The maximum OS text scale applied on the caption subtree (NFR-2): 200%.
const double kMaxCaptionTextScale = 2.0;

/// Renders the live caption turns with confidence emphasis and the resident's
/// accessibility settings. Pass the accumulated [turns] (from the tested
/// TurnAccumulator) and the current [settings].
class CaptionSurface extends StatelessWidget {
  const CaptionSurface({
    super.key,
    required this.turns,
    required this.settings,
    this.emptyPlaceholder = 'Captions appear here as your visitor speaks.',
  });

  /// The accumulated caption turns to render, oldest first.
  final List<CaptionTurn> turns;

  /// The resident's settings. [captionForeground] is already enforced to meet
  /// the 4.5:1 floor by ThresholdSettings; [captionScale] is clamped to [1,2].
  final ThresholdSettings settings;

  /// Shown before any caption arrives. Dash-free (NFR-10).
  final String emptyPlaceholder;

  @override
  Widget build(BuildContext context) {
    final Color fg = settings.captionForeground;
    final double fontSize = kBaseCaptionFontSize * settings.captionScale;

    // Clamp OS dynamic type to 200% on this subtree so a large system setting
    // stacked on top of the caption scale never exceeds the NFR-2 ceiling.
    final MediaQueryData mq = MediaQuery.of(context);
    final TextScaler clamped = mq.textScaler.clamp(
      minScaleFactor: 1.0,
      maxScaleFactor: kMaxCaptionTextScale,
    );

    final Widget content = turns.isEmpty
        ? Text(
            emptyPlaceholder,
            key: const ValueKey('caption-empty'),
            style: TextStyle(color: fg, fontSize: fontSize, height: 1.3),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var i = 0; i < turns.length; i++)
                _CaptionTurnText(
                  key: ValueKey('caption-turn-$i'),
                  turn: turns[i],
                  foreground: fg,
                  fontSize: fontSize,
                ),
            ],
          );

    return MediaQuery(
      data: mq.copyWith(textScaler: clamped),
      child: content,
    );
  }
}

/// Renders one turn as a run of tokens, each styled per its emphasis. A partial
/// turn is whole-fragment provisional (FR-5.3); a finalized turn styles each
/// token by confidence against the 0.6 threshold (FR-5.3a).
class _CaptionTurnText extends StatelessWidget {
  const _CaptionTurnText({
    super.key,
    required this.turn,
    required this.foreground,
    required this.fontSize,
  });

  final CaptionTurn turn;
  final Color foreground;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    // Split the turn text into tokens. A partial has no per-token confidence, so
    // the whole fragment is provisional; a finalized turn carries a single
    // confidence for the fragment (the engine's turn-level confidence).
    final List<String> words = turn.text.trim().isEmpty
        ? const <String>[]
        : turn.text.trim().split(RegExp(r'\s+'));

    final List<InlineSpan> spans = <InlineSpan>[];
    for (var i = 0; i < words.length; i++) {
      final token = CaptionToken(text: words[i], confidence: turn.confidence);
      final emphasis = emphasisForToken(token, isFinal: turn.isFinal);
      spans.add(
        TextSpan(
          text: i == 0 ? words[i] : ' ${words[i]}',
          style: _styleFor(emphasis),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(children: spans),
        style: TextStyle(color: foreground, fontSize: fontSize, height: 1.3),
      ),
    );
  }

  TextStyle _styleFor(CaptionEmphasis emphasis) {
    switch (emphasis) {
      case CaptionEmphasis.provisional:
        // Whole-fragment provisional: de-emphasized, italic, never "certain".
        return TextStyle(
          color: foreground.withValues(alpha: 0.6),
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w400,
        );
      case CaptionEmphasis.lowConfidence:
        // Finalized but low confidence (< 0.6): de-emphasized.
        return TextStyle(
          color: foreground.withValues(alpha: 0.6),
          fontWeight: FontWeight.w400,
        );
      case CaptionEmphasis.normal:
        // Finalized and confident (>= 0.6): full-strength normal style.
        return TextStyle(
          color: foreground,
          fontWeight: FontWeight.w600,
        );
    }
  }
}

/// Whether the given emphasis renders de-emphasized (provisional or low
/// confidence). Exposed for widget tests that assert the rendered style.
bool captionEmphasisIsDeEmphasized(CaptionEmphasis emphasis) =>
    isDeEmphasized(emphasis);
