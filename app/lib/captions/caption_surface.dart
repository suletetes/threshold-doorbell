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
// emphasis to a rendered style. No dashes appear in any label (NFR-10).
//
// --- Presentation (UI/UX audit C7) -------------------------------------------
//
// The audit's finding was that this is "the hero surface of the entire product
// and it is styled like a debug overlay": confidence mapped to opacity and
// weight only, with no speaker attribution and no treatment for provisional text
// beyond raw alpha. Three changes, all expression, none logic:
//
//   1. Per-turn speaker attribution. A turn now says who is talking, with an
//      icon, so a run of alternating turns is scannable instead of a wall of
//      text. The attribution is a SIBLING of the caption text, not a child of
//      it, so the caption text node stays exactly one Text per turn.
//   2. Provisional text gets a deliberate treatment rather than only alpha: it
//      keeps the reduced alpha and the italic (both load bearing, asserted by
//      AT-4) and adds a dotted underline plus an explicit "Still listening"
//      marker on the turn. Alpha alone is ambiguous; a dotted underline is the
//      conventional "not settled yet" signal and survives being photographed,
//      screenshotted, or viewed at 200% scale.
//   3. The three caption semantic roles are used for the chrome, passed through
//      enforceContrastFloor against the resident's caption background. That
//      reuses the existing FR-10.2 enforcement rather than inventing a second
//      contrast rule, so a role color can never be the thing that becomes
//      illegible on someone's chosen background.
//
// What deliberately did NOT change: the caption TEXT color is still exactly
// settings.captionForeground (the enforced floor), the emphasis mapping is still
// exactly provisional/lowConfidence/normal, and the 200% clamp is still applied
// to this subtree.

import 'package:flutter/material.dart';

import '../design/colors.dart';
import '../design/components/components.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../settings/contrast.dart';
import '../settings/settings_state.dart';
import 'caption_styling.dart';
import 'turn_segmentation.dart';

/// The base caption font size at scale 1.0. Multiplied by the resident's caption
/// scale (FR-10.2). Kept generous for the dominant caption surface (design
/// section 8.2): it is the type scale's largest title role, which is the optical
/// size the scale reserves for text that has to be read at a glance. Derived
/// rather than restated so captions cannot drift off the scale (audit C3).
final double kBaseCaptionFontSize = ThresholdTypography.base.titleLarge!.fontSize!;

/// The maximum OS text scale applied on the caption subtree (NFR-2): 200%.
const double kMaxCaptionTextScale = 2.0;

/// The line height multiplier for caption text. Looser than running copy: this
/// text updates live and is read in glances, so the lines need to stay separable.
final double kCaptionLineHeight = ThresholdTypography.base.titleLarge!.height!;

/// The alpha applied to de-emphasized caption text (provisional and finalized
/// below the 0.6 confidence threshold). Load bearing: AT-4 asserts that a
/// de-emphasized token renders at less than full alpha.
const double kDeEmphasizedCaptionAlpha = 0.6;

/// The marker shown on a turn that has not been finalized yet (FR-5.3). Dash
/// free (NFR-10).
const String kProvisionalTurnMarker = 'Still listening';

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

  /// The label for a turn's speaker. Dash-free (NFR-10).
  static String speakerLabel(CaptionSpeaker speaker) {
    switch (speaker) {
      case CaptionSpeaker.visitor:
        return 'Visitor';
      case CaptionSpeaker.resident:
        return 'You';
    }
  }

  /// The icon for a turn's speaker. Audit section 4, "Iconography": there were
  /// effectively no icons anywhere, and they are the primary scanning aid here.
  static IconData speakerIcon(CaptionSpeaker speaker) {
    switch (speaker) {
      case CaptionSpeaker.visitor:
        return Icons.person_outline;
      case CaptionSpeaker.resident:
        return Icons.record_voice_over_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color fg = settings.captionForeground;
    final double fontSize = kBaseCaptionFontSize * settings.captionScale;
    final semantic = ThresholdSemanticColors.of(context);

    // The caption semantic roles, pushed through the SAME enforcement the
    // caption foreground already goes through (FR-10.2, NFR-2). The roles decide
    // the intent; enforceContrastFloor decides whether that intent is legible on
    // this resident's caption background. No second contrast rule.
    final Color attributionColor = enforceContrastFloor(
      semantic.captionOnSurface,
      settings.captionBackground,
    );
    final Color provisionalChromeColor = enforceContrastFloor(
      semantic.captionProvisional,
      settings.captionBackground,
    );

    // Clamp OS dynamic type to 200% on this subtree so a large system setting
    // stacked on top of the caption scale never exceeds the NFR-2 ceiling.
    final MediaQueryData mq = MediaQuery.of(context);
    final TextScaler clamped = mq.textScaler.clamp(
      minScaleFactor: 1.0,
      maxScaleFactor: kMaxCaptionTextScale,
    );

    final Widget content = turns.isEmpty
        ? EmptyState(
            icon: Icons.closed_caption_off_outlined,
            title: emptyPlaceholder,
            titleKey: const ValueKey('caption-empty'),
            foreground: fg,
            semanticsLabel: emptyPlaceholder,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var i = 0; i < turns.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    top: i == 0 ? Spacing.space0 : Spacing.space3,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // Attribution is a sibling of the caption text, never a
                      // child of it, so one turn is still exactly one Text node.
                      _SpeakerAttribution(
                        key: ValueKey('caption-speaker-$i'),
                        turn: turns[i],
                        color: attributionColor,
                        provisionalColor: provisionalChromeColor,
                      ),
                      _CaptionTurnText(
                        key: ValueKey('caption-turn-$i'),
                        turn: turns[i],
                        foreground: fg,
                        fontSize: fontSize,
                        provisionalChrome: provisionalChromeColor,
                      ),
                    ],
                  ),
                ),
            ],
          );

    return MediaQuery(
      data: mq.copyWith(textScaler: clamped),
      child: content,
    );
  }
}

/// Who is speaking in this turn, plus the provisional marker while the turn is
/// still open (audit C7: "clear speaker attribution per turn"). Rendered small
/// and quiet so it labels the caption without competing with it.
class _SpeakerAttribution extends StatelessWidget {
  const _SpeakerAttribution({
    super.key,
    required this.turn,
    required this.color,
    required this.provisionalColor,
  });

  final CaptionTurn turn;

  /// The enforced attribution color.
  final Color color;

  /// The enforced provisional chrome color.
  final Color provisionalColor;

  @override
  Widget build(BuildContext context) {
    final label = CaptionSurface.speakerLabel(turn.speaker);
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.space1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            CaptionSurface.speakerIcon(turn.speaker),
            size: Spacing.space4,
            color: color,
          ),
          const SizedBox(width: Spacing.space1),
          Text(label, style: style),
          if (!turn.isFinal) ...<Widget>[
            const SizedBox(width: Spacing.space2),
            // The provisional marker: says in words what the dotted underline
            // and the reduced emphasis say visually (FR-5.3).
            Text(
              kProvisionalTurnMarker,
              key: const ValueKey('caption-provisional-marker'),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: provisionalColor, fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
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
    required this.provisionalChrome,
  });

  final CaptionTurn turn;
  final Color foreground;
  final double fontSize;

  /// The enforced color used for the provisional underline.
  final Color provisionalChrome;

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

    return Text.rich(
      TextSpan(children: spans),
      style: TextStyle(
        color: foreground,
        fontSize: fontSize,
        height: kCaptionLineHeight,
      ),
    );
  }

  TextStyle _styleFor(CaptionEmphasis emphasis) {
    switch (emphasis) {
      case CaptionEmphasis.provisional:
        // Whole-fragment provisional: de-emphasized, italic, never "certain",
        // and now explicitly marked as unsettled with a dotted underline rather
        // than relying on alpha alone to carry that meaning (audit C7).
        return TextStyle(
          color: foreground.withValues(alpha: kDeEmphasizedCaptionAlpha),
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w400,
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.dotted,
          decorationColor: provisionalChrome,
        );
      case CaptionEmphasis.lowConfidence:
        // Finalized but low confidence (< 0.6): de-emphasized.
        return TextStyle(
          color: foreground.withValues(alpha: kDeEmphasizedCaptionAlpha),
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
