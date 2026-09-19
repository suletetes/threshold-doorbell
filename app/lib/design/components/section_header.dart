// Section header (UI/UX audit section 4, "Information architecture": settings was
// a flat list with no grouping hierarchy despite containing at least four
// distinct concerns, and its inline `_section` helper used a raw fontSize of 18
// with a raw w700).
//
// Deliberately NOT all caps. All caps micro-labels are the current fashion in
// dashboard UI, but they measurably slow reading and defeat word-shape
// recognition, and this is a product for people with a sensory impairment. The
// hierarchy comes from the type scale, the role color, and a leading accent rule
// instead.

import 'package:flutter/material.dart';

import '../tokens.dart';

/// A labelled group boundary in a long surface.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.supportingText,
    this.dense = false,
  });

  /// The group name, sentence case. Dash-free (NFR-10).
  final String title;

  /// One line explaining what the group controls, when the name is not enough.
  final String? supportingText;

  /// A subordinate header inside an existing group: no accent rule, tighter
  /// leading space, one step down the type scale.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final String? supporting = supportingText;

    // A dense header is genuinely subordinate: one step down the label scale and
    // the variant text color, not just tighter padding.
    final Widget label = Text(
      title,
      style: (dense ? theme.textTheme.labelMedium : theme.textTheme.titleSmall)
          ?.copyWith(color: dense ? scheme.onSurfaceVariant : scheme.onSurface),
    );

    return Semantics(
      header: true,
      label: title,
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.only(
          top: dense ? Spacing.space4 : Spacing.space6,
          bottom: Spacing.space2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (!dense) ...<Widget>[
                  // The accent rule: hierarchy without shouting.
                  _AccentRule(color: scheme.primary),
                  const SizedBox(width: Spacing.space3),
                ],
                Expanded(child: label),
              ],
            ),
            if (supporting != null) ...<Widget>[
              const SizedBox(height: Spacing.space1),
              Padding(
                padding: EdgeInsets.only(
                  left: dense ? Spacing.space0 : _AccentRule.width + Spacing.space3,
                ),
                child: Text(
                  supporting,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccentRule extends StatelessWidget {
  const _AccentRule({required this.color});

  static const double width = Spacing.space1;
  static const double height = Spacing.space5;

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color, borderRadius: Radii.roundedFull),
      child: const SizedBox(width: width, height: height),
    );
  }
}
