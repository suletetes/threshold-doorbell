// The ThemeData factory for Threshold (UI/UX audit C1, and section 3.1: "ship a
// real theme with light and dark").
//
// Before this, main.dart shipped a one-line theme: ColorScheme.fromSeed plus
// useMaterial3 and nothing else. No typography, no component themes, and no
// dark theme at all, on a product that is used at the door at night. Every
// screen therefore styled itself inline and drifted from every other screen.
//
// Component themes are the leverage here: because the screens currently fall
// back to stock Material defaults everywhere, theming the components lifts all
// of them at once without editing a single screen file.
//
// The button themes enforce the 48dp minimum interactive dimension
// (TouchTarget.minimum). Audit section 4 flagged that buttons used an inner
// Padding(vertical: 12) which lands near but not provably at 48dp, and that
// nothing in the codebase asserted the minimum. Now the theme does, and
// test/design/theme_test.dart asserts the theme does.

import 'package:flutter/material.dart';

import 'colors.dart';
import 'tokens.dart';
import 'typography.dart';

/// Builds the app themes. `ThresholdTheme.light()` and `ThresholdTheme.dark()`
/// are the only two themes the app has; both are designed, not derived.
abstract final class ThresholdTheme {
  /// The light theme.
  static ThemeData light() => _build(ThresholdColors.light, ThresholdSemanticColors.light);

  /// The dark theme. First-class, not a derivation of the light one
  /// (audit design principle 7).
  static ThemeData dark() => _build(ThresholdColors.dark, ThresholdSemanticColors.dark);

  static ThemeData _build(ColorScheme scheme, ThresholdSemanticColors semantic) {
    final text = ThresholdTypography.forScheme(scheme);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,

      // The semantic roles the product has but Material does not. Screens read
      // these through ThresholdSemanticColors.of(context).
      extensions: <ThemeExtension<dynamic>>[semantic],

      // --- Buttons. All three enforce the 48dp minimum target. ---
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: TouchTarget.minimumButtonSize,
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.space6,
            vertical: Spacing.space3,
          ),
          shape: const RoundedRectangleBorder(borderRadius: Radii.roundedLarge),
          textStyle: text.labelLarge,
          elevation: Elevations.level0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: TouchTarget.minimumButtonSize,
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.space6,
            vertical: Spacing.space3,
          ),
          shape: const RoundedRectangleBorder(borderRadius: Radii.roundedLarge),
          textStyle: text.labelLarge,
          foregroundColor: scheme.primary,
          // 1.5 rather than the stock hairline: a secondary action still has to
          // be visible to someone who cannot resolve a 1px edge.
          side: BorderSide(color: scheme.outline, width: 1.5),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: TouchTarget.minimumButtonSize,
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.space4,
            vertical: Spacing.space3,
          ),
          shape: const RoundedRectangleBorder(borderRadius: Radii.roundedMedium),
          textStyle: text.labelLarge,
          foregroundColor: scheme.primary,
        ),
      ),

      // --- Surfaces ---
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        elevation: Elevations.level1,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shadowColor: scheme.shadow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.roundedExtraLarge,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: Elevations.level3,
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: Radii.roundedExtraLarge),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: Spacing.space5,
          vertical: Spacing.space6,
        ),
      ),
      appBarTheme: AppBarThemeData(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: Elevations.level0,
        scrolledUnderElevation: Elevations.level2,
        shadowColor: scheme.shadow,
        centerTitle: false,
        titleSpacing: Spacing.space5,
        titleTextStyle: text.titleLarge,
        toolbarTextStyle: text.bodyMedium,
        iconTheme: IconThemeData(color: scheme.onSurface, size: Spacing.space6),
        actionsIconTheme: IconThemeData(color: scheme.onSurface, size: Spacing.space6),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        elevation: Elevations.level3,
        insetPadding: const EdgeInsets.all(Spacing.space4),
        shape: const RoundedRectangleBorder(borderRadius: Radii.roundedMedium),
      ),

      // --- Controls. The settings screen is the longest surface in the app and
      // is built out of these three. ---
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) return scheme.onSurface.withValues(alpha: 0.38);
          return states.contains(WidgetState.selected) ? scheme.onPrimary : scheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return scheme.onSurface.withValues(alpha: 0.12);
          }
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
          return states.contains(WidgetState.selected) ? Colors.transparent : scheme.outline;
        }),
      ),
      sliderTheme: SliderThemeData(
        // Thicker than stock: the caption size slider is dragged one-handed at
        // the door.
        trackHeight: 6,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
        valueIndicatorColor: scheme.inverseSurface,
        valueIndicatorTextStyle: text.labelLarge?.copyWith(color: scheme.onInverseSurface),
        activeTickMarkColor: scheme.onPrimary,
        inactiveTickMarkColor: scheme.outline,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Spacing.space5,
          vertical: Spacing.space2,
        ),
        minVerticalPadding: Spacing.space3,
        shape: const RoundedRectangleBorder(borderRadius: Radii.roundedMedium),
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        leadingAndTrailingTextStyle: text.labelMedium,
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
      ),

      // --- Shared chrome ---
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: Spacing.space4,
      ),
      iconTheme: IconThemeData(color: scheme.onSurface, size: Spacing.space6),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),
    );
  }
}
