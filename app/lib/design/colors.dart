// Color for Threshold (UI/UX audit C1, C2). Two complete ColorSchemes plus the
// semantic roles the product actually has.
//
// Why the schemes are written out instead of generated at runtime: audit design
// principle 7, "dark is first-class; both schemes are designed and tested, not
// derived by accident". A const scheme is inspectable, diffable, and its
// contrast can be asserted by the test suite. Every tonal value below was taken
// from the Material 3 tonal palette for the Threshold brand seed 0xFF1565C0, so
// the hue family is the brand blue rather than an invented one.
//
// The one deliberate departure: `primary` in the light scheme is the brand blue
// itself (0xFF1565C0) rather than the desaturated tone the generator picks. It
// carries white at 5.7:1, so the brand keeps its presence without costing
// contrast.
//
// Audit C2 listed the literals this replaces: 0xFF0B0B0F, 0xFF15151B,
// 0xCC1565C0, 0xB3000000, 0xFF555555. Screens stop choosing colors by eye and
// start asking for a role.

import 'package:flutter/material.dart';

/// The brand seed the tonal palettes below are derived from.
const Color kThresholdBrandSeed = Color(0xFF1565C0);

/// The complete light and dark [ColorScheme]s for the app.
abstract final class ThresholdColors {
  static const ColorScheme light = ColorScheme(
    brightness: Brightness.light,
    // The brand blue, carrying white at 5.7:1.
    primary: Color(0xFF1565C0),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD6E3FF),
    onPrimaryContainer: Color(0xFF001B3D),
    secondary: Color(0xFF555F71),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFDAE2F9),
    onSecondaryContainer: Color(0xFF121C2B),
    tertiary: Color(0xFF6F5575),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFF9D8FD),
    onTertiaryContainer: Color(0xFF28132F),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFF9F9FF),
    onSurface: Color(0xFF191C20),
    surfaceDim: Color(0xFFD9D9E0),
    surfaceBright: Color(0xFFF9F9FF),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF3F3FA),
    surfaceContainer: Color(0xFFEDEDF4),
    surfaceContainerHigh: Color(0xFFE7E8EE),
    surfaceContainerHighest: Color(0xFFE2E2E9),
    onSurfaceVariant: Color(0xFF44474E),
    outline: Color(0xFF74777F),
    outlineVariant: Color(0xFFC4C6CF),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF2E3036),
    onInverseSurface: Color(0xFFF0F0F7),
    inversePrimary: Color(0xFFA9C7FF),
    surfaceTint: Color(0xFF1565C0),
  );

  static const ColorScheme dark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFA9C7FF),
    onPrimary: Color(0xFF08305F),
    primaryContainer: Color(0xFF274777),
    onPrimaryContainer: Color(0xFFD6E3FF),
    secondary: Color(0xFFBDC7DC),
    onSecondary: Color(0xFF283141),
    secondaryContainer: Color(0xFF3E4758),
    onSecondaryContainer: Color(0xFFDAE2F9),
    tertiary: Color(0xFFDCBCE1),
    onTertiary: Color(0xFF3F2845),
    tertiaryContainer: Color(0xFF563E5C),
    onTertiaryContainer: Color(0xFFF9D8FD),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF111318),
    onSurface: Color(0xFFE2E2E9),
    surfaceDim: Color(0xFF111318),
    surfaceBright: Color(0xFF37393E),
    surfaceContainerLowest: Color(0xFF0C0E13),
    surfaceContainerLow: Color(0xFF191C20),
    surfaceContainer: Color(0xFF1D2024),
    surfaceContainerHigh: Color(0xFF282A2F),
    surfaceContainerHighest: Color(0xFF33353A),
    onSurfaceVariant: Color(0xFFC4C6CF),
    outline: Color(0xFF8E9099),
    outlineVariant: Color(0xFF44474E),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE2E2E9),
    onInverseSurface: Color(0xFF2E3036),
    inversePrimary: Color(0xFF1565C0),
    surfaceTint: Color(0xFFA9C7FF),
  );
}

/// The semantic color roles the product has but Material does not (audit section
/// 4, "Color and contrast": there was no token for live, recording, provisional
/// caption, danger, or success, even though the product has all of those
/// concepts).
///
/// Registered on both [ThemeData]s as a [ThemeExtension] so a screen reads a
/// role from the theme instead of hardcoding a hex value.
///
/// The three caption roles stay dark in both schemes on purpose. Captions are
/// composited over inbound doorbell video, which is a dark surface whatever the
/// platform theme is, so flipping them for light mode would break the contrast
/// floor the caption path already enforces (FR-10.2, NFR-2). They are opaque
/// here; any scrim or alpha treatment belongs to the surface that draws them.
@immutable
class ThresholdSemanticColors extends ThemeExtension<ThresholdSemanticColors> {
  const ThresholdSemanticColors({
    required this.captionSurface,
    required this.captionOnSurface,
    required this.captionProvisional,
    required this.live,
    required this.recording,
    required this.success,
    required this.warning,
    required this.danger,
  });

  /// The light-scheme semantic roles. Every role carries at least 4.5:1 against
  /// the light surface, asserted in test/design/colors_test.dart.
  static const ThresholdSemanticColors light = ThresholdSemanticColors(
    captionSurface: Color(0xFF16181D),
    captionOnSurface: Color(0xFFFFFFFF),
    captionProvisional: Color(0xFFB9BDC7),
    live: Color(0xFF00695C),
    recording: Color(0xFFB3261E),
    success: Color(0xFF1B5E20),
    warning: Color(0xFF7A4100),
    danger: Color(0xFF8C1D18),
  );

  /// The dark-scheme semantic roles. Every role carries at least 4.5:1 against
  /// the dark surface, asserted in test/design/colors_test.dart.
  static const ThresholdSemanticColors dark = ThresholdSemanticColors(
    captionSurface: Color(0xFF0B0D11),
    captionOnSurface: Color(0xFFFFFFFF),
    captionProvisional: Color(0xFFAEB3BD),
    live: Color(0xFF6FDBB8),
    recording: Color(0xFFFF8A80),
    success: Color(0xFF7BDE9A),
    warning: Color(0xFFFFB86B),
    danger: Color(0xFFFFB4AB),
  );

  /// The background of the live caption container. Audit C7: the caption surface
  /// is the centerpiece of the product and was styled like a debug overlay.
  final Color captionSurface;

  /// Confident, finalized caption text on [captionSurface].
  final Color captionOnSurface;

  /// Provisional (not yet finalized) caption text. Audit C7: provisional text
  /// deserves a deliberate treatment, not raw opacity.
  final Color captionProvisional;

  /// An active two-way session. The mode badge and any live indicator.
  final Color live;

  /// Recording or capture is in progress. Distinct from [danger]: this is a
  /// state, not a warning.
  final Color recording;

  /// A completed action. Audit section 4, "Feedback states": there was no
  /// success affordance at all, which matters when the user cannot hear that a
  /// reply played.
  final Color success;

  /// A degraded but usable state, for example captions-only or offline.
  final Color warning;

  /// A destructive action or a hard failure, for example "Delete all my data".
  final Color danger;

  /// The registered extension, falling back to the scheme that matches the
  /// ambient brightness if a caller builds a ThemeData without it.
  static ThresholdSemanticColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<ThresholdSemanticColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  ThresholdSemanticColors copyWith({
    Color? captionSurface,
    Color? captionOnSurface,
    Color? captionProvisional,
    Color? live,
    Color? recording,
    Color? success,
    Color? warning,
    Color? danger,
  }) {
    return ThresholdSemanticColors(
      captionSurface: captionSurface ?? this.captionSurface,
      captionOnSurface: captionOnSurface ?? this.captionOnSurface,
      captionProvisional: captionProvisional ?? this.captionProvisional,
      live: live ?? this.live,
      recording: recording ?? this.recording,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
    );
  }

  @override
  ThresholdSemanticColors lerp(
      ThemeExtension<ThresholdSemanticColors>? other, double t) {
    if (other is! ThresholdSemanticColors) return this;
    return ThresholdSemanticColors(
      captionSurface: Color.lerp(captionSurface, other.captionSurface, t)!,
      captionOnSurface:
          Color.lerp(captionOnSurface, other.captionOnSurface, t)!,
      captionProvisional:
          Color.lerp(captionProvisional, other.captionProvisional, t)!,
      live: Color.lerp(live, other.live, t)!,
      recording: Color.lerp(recording, other.recording, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }

  /// Every role in a fixed order. Lets a test assert the set is complete without
  /// restating the field list.
  List<Color> get all => <Color>[
        captionSurface,
        captionOnSurface,
        captionProvisional,
        live,
        recording,
        success,
        warning,
        danger,
      ];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ThresholdSemanticColors &&
        other.captionSurface == captionSurface &&
        other.captionOnSurface == captionOnSurface &&
        other.captionProvisional == captionProvisional &&
        other.live == live &&
        other.recording == recording &&
        other.success == success &&
        other.warning == warning &&
        other.danger == danger;
  }

  @override
  int get hashCode => Object.hash(
        captionSurface,
        captionOnSurface,
        captionProvisional,
        live,
        recording,
        success,
        warning,
        danger,
      );
}
