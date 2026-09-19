// Empty state (UI/UX audit section 4, "Feedback states": the caption empty state
// was a single line of placeholder text, "acceptable but unstyled", and no other
// surface had an empty treatment at all).
//
// An empty state has to answer two questions at a glance: is this broken, and
// what happens next. The icon answers the first, the supporting line answers the
// second.

import 'package:flutter/material.dart';

import '../tokens.dart';

/// A surface with nothing in it yet, stated deliberately.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.supportingText,
    this.action,
    this.foreground,
    this.semanticsLabel,
    this.titleKey,
  });

  final IconData icon;

  /// What is empty, in plain language. Dash-free (NFR-10).
  final String title;

  /// What will fill it, or what to do about it.
  final String? supportingText;

  /// An optional single action.
  final Widget? action;

  /// Overrides the text and icon color. The caption surface passes the enforced
  /// >=4.5:1 caption foreground here (FR-10.2, NFR-2), because on that surface
  /// the contrast floor, not the theme, decides what is legible.
  final Color? foreground;

  /// Defaults to [title] plus [supportingText], read as one announcement.
  final String? semanticsLabel;

  /// Key placed on the title [Text] so existing widget tests keep working.
  final Key? titleKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final Color fg = foreground ?? scheme.onSurface;
    final Color supportingColor =
        foreground?.withValues(alpha: 0.75) ?? scheme.onSurfaceVariant;
    final String? supporting = supportingText;
    final Widget? actionWidget = action;

    return Semantics(
      label: semanticsLabel ??
          (supporting == null ? title : '$title $supporting'),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: Spacing.space7, color: supportingColor),
          const SizedBox(height: Spacing.space3),
          Text(
            title,
            key: titleKey,
            style: theme.textTheme.titleMedium?.copyWith(color: fg),
          ),
          if (supporting != null) ...<Widget>[
            const SizedBox(height: Spacing.space1),
            Text(
              supporting,
              style: theme.textTheme.bodyMedium?.copyWith(color: supportingColor),
            ),
          ],
          if (actionWidget != null) ...<Widget>[
            const SizedBox(height: Spacing.space4),
            actionWidget,
          ],
        ],
      ),
    );
  }
}
