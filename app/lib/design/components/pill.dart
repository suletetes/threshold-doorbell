// Shared badge (UI/UX audit section 4, "Component consistency": `_ModeBadge`
// was a bespoke pill that existed nowhere else, built from a raw 0xCC1565C0 and
// a raw radius of 16).
//
// A pill states a fact about the current surface: the live caption mode, a
// recording indicator, a provisional marker. It is never interactive, so the
// 48dp minimum target does not apply to it; it is deliberately not built on
// Chip, which carries tap affordance and Material's own padding opinions.
//
// Contrast: the fill is the role tinted over the surface, which composites to an
// OPAQUE color, and the label and icon are the role itself. That matters because
// this pill is drawn over inbound doorbell video on the conversation screen, and
// a translucent badge over unknown video content has no contrast guarantee.

import 'package:flutter/material.dart';

import '../tokens.dart';

/// A small, opaque, non-interactive badge carrying a semantic role color.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.semanticsLabel,
  });

  /// The badge text. Dash-free (NFR-10).
  final String label;

  /// The semantic role this pill stands for, for example
  /// `ThresholdSemanticColors.of(context).live`.
  final Color color;

  /// Leading icon. Audit section 4: the old mode badge was text only.
  final IconData? icon;

  /// Defaults to [label]. Set it when the spoken form should be richer, for
  /// example 'Active caption mode: Clarity Mode'.
  final String? semanticsLabel;

  /// How much of the role is mixed into the surface to make the fill.
  ///
  /// Kept low on purpose. Each role is designed to carry at least 4.5:1 against
  /// the scheme surface, and the label is the role itself, so the closer the fill
  /// stays to the surface the more of that guarantee survives. A heavier tint
  /// walks the label toward its own background: at 0.20 the light-scheme
  /// `recording` role lands at 4.47:1, which is a failure, not a rounding error.
  static const double fillTintAlpha = 0.12;

  /// How much of the role is used for the outline.
  static const double borderTintAlpha = 0.55;

  /// The opaque fill this pill paints for [color]. Exposed so a test can assert
  /// the contrast of the composite the widget actually draws.
  static Color fillFor(BuildContext context, Color color) => Color.alphaBlend(
        color.withValues(alpha: fillTintAlpha),
        Theme.of(context).colorScheme.surface,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final IconData? leading = icon;

    return Semantics(
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // Opaque by construction: a tint over an opaque surface.
          color: fillFor(context, color),
          borderRadius: Radii.roundedFull,
          border: Border.all(
            color: color.withValues(alpha: borderTintAlpha),
            width: 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.space3,
            vertical: Spacing.space2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (leading != null) ...<Widget>[
                Icon(leading, size: Spacing.space4, color: color),
                const SizedBox(width: Spacing.space2),
              ],
              // Flexible so a hostile OS text scale wraps the label instead of
              // overflowing the badge. A pill sits outside the caption subtree,
              // so it does not get the 200% clamp and has to cope with whatever
              // the platform hands it.
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
