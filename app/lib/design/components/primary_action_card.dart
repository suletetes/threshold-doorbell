// The hero action (UI/UX audit C5: "the primary action has no visual weight").
//
// The home screen previously put a paragraph of 18px text, a stock FilledButton
// reading "Answer the door", a helper line, and an OutlinedButton reading
// "Settings" in a Column. "Answer the door" is the entire reason the product
// exists and it looked identical in weight to Settings.
//
// This is the fix: a large tonal card with an icon in a filled badge, a headline
// label, a supporting status line, and a forward affordance. Audit design
// principle 6: the hero action must be identifiable in under a second.
//
// Motion (audit C6 and design principle 3): the only animation is a press scale,
// it communicates "this is the thing you pressed", and it runs through
// motionDuration() so a reduced-motion user gets no movement at all.

import 'package:flutter/material.dart';

import '../tokens.dart';

/// The hero action on a screen. There is at most one per screen.
class PrimaryActionCard extends StatefulWidget {
  const PrimaryActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.supportingText,
    this.semanticsLabel,
    this.trailingIcon = Icons.arrow_forward_rounded,
  });

  /// The action's icon, rendered in a filled badge. Audit section 4,
  /// "Iconography": home had no icons at all.
  final IconData icon;

  /// The action, as an imperative phrase. Dash-free (NFR-10).
  final String label;

  final VoidCallback onPressed;

  /// The status line under the label: what happens when this is pressed, or the
  /// current readiness of the thing it acts on.
  final String? supportingText;

  /// Defaults to [label]. The card excludes its inner semantics so a screen
  /// reader announces one button, not three fragments.
  final String? semanticsLabel;

  final IconData trailingIcon;

  /// The hero's minimum height, in dp. Two minimum touch targets tall: the point
  /// is that it cannot be mistaken for a secondary control.
  static const double minimumHeight = TouchTarget.minimum * 2;

  /// How far the card scales down while pressed.
  static const double pressedScale = 0.98;

  @override
  State<PrimaryActionCard> createState() => _PrimaryActionCardState();
}

class _PrimaryActionCardState extends State<PrimaryActionCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final String? supporting = widget.supportingText;

    return Semantics(
      button: true,
      label: widget.semanticsLabel ?? widget.label,
      // Give the merged node a real tap action so TalkBack / VoiceOver
      // double-tap activates it (HIGH-06). excludeSemantics merges the inner
      // button away for a single clean node, but that also drops the inner
      // tap action, so it is reinstated here on the wrapper.
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: AnimatedScale(
        scale: _pressed ? PrimaryActionCard.pressedScale : 1,
        duration: motionDuration(context, Motion.fast),
        curve: Motion.standardCurve,
        child: Material(
          color: scheme.primaryContainer,
          elevation: Elevations.level2,
          shadowColor: scheme.shadow,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: Radii.roundedExtraLarge,
            side: BorderSide(
                color: scheme.primary.withValues(alpha: 0.35), width: 1.5),
          ),
          child: InkWell(
            onTap: widget.onPressed,
            onTapDown: (_) => _setPressed(true),
            onTapUp: (_) => _setPressed(false),
            onTapCancel: () => _setPressed(false),
            borderRadius: Radii.roundedExtraLarge,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                  minHeight: PrimaryActionCard.minimumHeight),
              child: Padding(
                padding: const EdgeInsets.all(Spacing.space5),
                child: Row(
                  children: <Widget>[
                    _IconBadge(icon: widget.icon),
                    const SizedBox(width: Spacing.space5),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.label,
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(color: scheme.onPrimaryContainer),
                          ),
                          if (supporting != null) ...<Widget>[
                            const SizedBox(height: Spacing.space1),
                            Text(
                              supporting,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onPrimaryContainer
                                    .withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: Spacing.space3),
                    Icon(
                      widget.trailingIcon,
                      color: scheme.onPrimaryContainer,
                      size: Spacing.space6,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The icon in a filled circle. The fill is `primary`, which carries `onPrimary`
/// at 5.7:1 in the light scheme by construction (see design/colors.dart).
class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.space3),
        child: Icon(icon, color: scheme.onPrimary, size: Spacing.space7),
      ),
    );
  }
}
