// Shared status banner (UI/UX audit section 3.6: "the Captions-Only banner, the
// offline state, the Privacy-Mode unavailable line, and the permission-denied
// explanation are four different ad hoc treatments of the same idea. One
// component, four semantic variants").
//
// Design principle 5 from the audit: one concept, one component. Every surface
// that states a condition now uses this, with the variant carrying the meaning.
//
// Contrast discipline: the message always renders in `onSurface`, and the
// background is only a light tint of the role over a container surface, so the
// body copy keeps the full surface contrast in both schemes. The role color is
// spent on the icon and the border, where it reads as meaning rather than as
// decoration. Each role already carries at least 4.5:1 against the surface
// (asserted in test/design/colors_test.dart), so it stays legible as an outline.

import 'package:flutter/material.dart';

import '../colors.dart';
import '../tokens.dart';

/// The four semantic conditions a banner can state.
enum StatusVariant {
  /// A neutral fact the resident should know.
  info,

  /// A degraded but usable state, for example captions only or offline.
  warning,

  /// A hard failure or a destructive consequence.
  danger,

  /// Something completed.
  success,
}

/// The optional action a banner can offer. Kept as data rather than a widget
/// slot so every banner action gets the same weight, icon treatment, minimum
/// target size, and semantics without each call site restating them.
@immutable
class StatusBannerAction {
  const StatusBannerAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.buttonKey,
    this.semanticsLabel,
  });

  /// The visible button label. Also the default semantics label.
  final String label;

  final VoidCallback onPressed;

  /// Leading icon. Audit section 4, "Iconography": there were effectively no
  /// icons anywhere, and icons are the primary scanning aid in this class of app.
  final IconData? icon;

  /// Key placed on the button itself so existing widget tests keep working.
  final Key? buttonKey;

  final String? semanticsLabel;
}

/// A banner that states a condition, optionally with one recovery action.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.message,
    this.variant = StatusVariant.info,
    this.icon,
    this.action,
    this.semanticsLabel,
    this.liveRegion = true,
    this.messageKey,
  });

  /// The condition, in plain language. Dash-free (NFR-10).
  final String message;

  final StatusVariant variant;

  /// Overrides the variant's default icon.
  final IconData? icon;

  /// At most one action. A banner with two actions is a dialog.
  final StatusBannerAction? action;

  /// Defaults to [message]. Set it when the spoken form should differ.
  final String? semanticsLabel;

  /// Whether the message announces itself on change. True by default: a banner
  /// exists to report a condition, and this product's users get no audio cue.
  final bool liveRegion;

  /// Key placed on the message [Text] so existing widget tests keep working.
  final Key? messageKey;

  /// How much of the role is mixed into the container surface for the fill. A
  /// tint, not a fill: the message keeps the full surface contrast.
  static const double fillTintAlpha = 0.12;

  /// How much of the role is used for the outline and the action's fill.
  static const double borderTintAlpha = 0.45;

  /// The opaque background this banner paints for [variant]. Exposed so a test
  /// can assert the contrast of the composite the widget actually draws rather
  /// than of a second copy of the formula.
  static Color backgroundFor(BuildContext context, StatusVariant variant) =>
      Color.alphaBlend(
        colorFor(context, variant).withValues(alpha: fillTintAlpha),
        Theme.of(context).colorScheme.surfaceContainerLow,
      );

  /// The role color for [variant].
  static Color colorFor(BuildContext context, StatusVariant variant) {
    final semantic = ThresholdSemanticColors.of(context);
    switch (variant) {
      case StatusVariant.info:
        return Theme.of(context).colorScheme.primary;
      case StatusVariant.warning:
        return semantic.warning;
      case StatusVariant.danger:
        return semantic.danger;
      case StatusVariant.success:
        return semantic.success;
    }
  }

  /// The default icon for [variant].
  static IconData iconFor(StatusVariant variant) {
    switch (variant) {
      case StatusVariant.info:
        return Icons.info_outline;
      case StatusVariant.warning:
        return Icons.warning_amber_rounded;
      case StatusVariant.danger:
        return Icons.error_outline;
      case StatusVariant.success:
        return Icons.check_circle_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final role = colorFor(context, variant);
    final StatusBannerAction? bannerAction = action;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundFor(context, variant),
        borderRadius: Radii.roundedLarge,
        border: Border.all(
          color: role.withValues(alpha: borderTintAlpha),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(icon ?? iconFor(variant), color: role, size: Spacing.space6),
                const SizedBox(width: Spacing.space3),
                Expanded(
                  // container, so the message forms its OWN semantics node. A
                  // label with no actions is not a semantic boundary, so without
                  // this it merges into whatever labelled container encloses the
                  // banner and the live region announcement arrives as part of a
                  // larger blob. On this product that announcement is sometimes
                  // the only channel a fact has.
                  child: Semantics(
                    container: true,
                    liveRegion: liveRegion,
                    label: semanticsLabel ?? message,
                    excludeSemantics: true,
                    child: Text(
                      message,
                      key: messageKey,
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
                    ),
                  ),
                ),
              ],
            ),
            if (bannerAction != null) ...<Widget>[
              const SizedBox(height: Spacing.space4),
              Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  button: true,
                  label: bannerAction.semanticsLabel ?? bannerAction.label,
                  excludeSemantics: true,
                  child: _BannerButton(action: bannerAction, role: role),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The banner's action, rendered at real button weight (a filled tonal button,
/// not a text link). Audit section 5 asked specifically for the Captions-Only
/// "Open Ring app" action to get an icon and proper button weight; every banner
/// action inherits that here. The minimum target size comes from the theme.
class _BannerButton extends StatelessWidget {
  const _BannerButton({required this.action, required this.role});

  final StatusBannerAction action;
  final Color role;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = FilledButton.styleFrom(
      minimumSize: TouchTarget.minimumButtonSize,
      backgroundColor: Color.alphaBlend(
        role.withValues(alpha: StatusBanner.fillTintAlpha),
        scheme.surfaceContainerHigh,
      ),
      foregroundColor: scheme.onSurface,
      shape: const RoundedRectangleBorder(borderRadius: Radii.roundedMedium),
      side: BorderSide(
        color: role.withValues(alpha: StatusBanner.borderTintAlpha),
        width: 1.5,
      ),
    );
    final IconData? icon = action.icon;
    if (icon == null) {
      return FilledButton(
        key: action.buttonKey,
        onPressed: action.onPressed,
        style: style,
        child: Text(action.label),
      );
    }
    return FilledButton.icon(
      key: action.buttonKey,
      onPressed: action.onPressed,
      style: style,
      icon: Icon(icon, size: Spacing.space5),
      label: Text(action.label),
    );
  }
}
