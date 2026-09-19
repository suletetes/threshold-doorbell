// Type scale for Threshold (UI/UX audit C3). An explicit TextTheme with size,
// weight, line height, and letter spacing set for every Material 3 role.
//
// What this replaces: raw inline integers (18 on home, 22 in the caption
// surface, 20 on the status and error panels, 16, 14) with no line height
// except two sporadic `height: 1.3` values, no letter spacing at all, and a
// weight vocabulary of "regular, sometimes w600". Hierarchy was communicated by
// arbitrary numbers, which is why the screens read flat.
//
// Two deliberate accessibility departures from the stock Material 3 metrics:
//
//   1. The body and title roles are one step larger than stock. bodyLarge is 18
//      rather than 16 (the home screen had already reached for 18 by hand),
//      bodyMedium is 16 rather than 14, bodySmall is 14 rather than 12. Nothing
//      in this app renders text below 12. This is a product for people with a
//      sensory impairment; small text is not a style option here.
//   2. Tracking tightens as size grows and line height loosens as size shrinks.
//      Stock Material leaves bodyLarge at 0.5 tracking, which is too loose for
//      sustained reading at the sizes captions use.
//
// Heights are multipliers of the font size, so they scale correctly with the
// platform text scale factor (and with the 200% caption clamp).

import 'package:flutter/material.dart';

/// The app type scale.
abstract final class ThresholdTypography {
  /// The scale with no colors bound. Use [forScheme] to get the themed version.
  static const TextTheme base = TextTheme(
    // --- Display: reserved for a single hero number or word. ---
    displayLarge: TextStyle(
      fontSize: 57,
      fontWeight: FontWeight.w400,
      height: 1.12,
      letterSpacing: -0.25,
    ),
    displayMedium: TextStyle(
      fontSize: 45,
      fontWeight: FontWeight.w400,
      height: 1.16,
      letterSpacing: -0.15,
    ),
    displaySmall: TextStyle(
      fontSize: 36,
      fontWeight: FontWeight.w400,
      height: 1.22,
      letterSpacing: 0,
    ),

    // --- Headline: screen and hero-action headings. Weighted up from stock
    // w400 to w600, because hierarchy here has to survive a glance. ---
    headlineLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w600,
      height: 1.25,
      letterSpacing: 0,
    ),
    headlineMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w600,
      height: 1.29,
      letterSpacing: 0,
    ),
    headlineSmall: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      height: 1.33,
      letterSpacing: 0.05,
    ),

    // --- Title: section headers, app bar, card titles, list rows. ---
    titleLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      height: 1.36,
      letterSpacing: 0.05,
    ),
    titleMedium: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      height: 1.44,
      letterSpacing: 0.1,
    ),
    titleSmall: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.50,
      letterSpacing: 0.1,
    ),

    // --- Body: running copy. bodyLarge is the default reading size. ---
    bodyLarge: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w400,
      height: 1.56,
      letterSpacing: 0.15,
    ),
    bodyMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.50,
      letterSpacing: 0.15,
    ),
    bodySmall: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.43,
      letterSpacing: 0.2,
    ),

    // --- Label: buttons, pills, chips, captions on controls. ---
    labelLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.25,
      letterSpacing: 0.1,
    ),
    labelMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.29,
      letterSpacing: 0.3,
    ),
    labelSmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      height: 1.33,
      letterSpacing: 0.4,
    ),
  );

  /// The smallest font size anywhere in the scale. Nothing in this app renders
  /// text smaller than this.
  static const double minimumFontSize = 12;

  /// [base] with text colors bound to [scheme]. This is what `theme.dart` hands
  /// to [ThemeData], so a screen that reads `Theme.of(context).textTheme` gets a
  /// style that is already legible on the current surface.
  static TextTheme forScheme(ColorScheme scheme) => base.apply(
        displayColor: scheme.onSurface,
        bodyColor: scheme.onSurface,
      );

  /// The display roles, largest first.
  static List<TextStyle> displayRoles(TextTheme t) =>
      <TextStyle>[t.displayLarge!, t.displayMedium!, t.displaySmall!];

  /// The headline roles, largest first.
  static List<TextStyle> headlineRoles(TextTheme t) =>
      <TextStyle>[t.headlineLarge!, t.headlineMedium!, t.headlineSmall!];

  /// The title roles, largest first.
  static List<TextStyle> titleRoles(TextTheme t) =>
      <TextStyle>[t.titleLarge!, t.titleMedium!, t.titleSmall!];

  /// The body roles, largest first.
  static List<TextStyle> bodyRoles(TextTheme t) =>
      <TextStyle>[t.bodyLarge!, t.bodyMedium!, t.bodySmall!];

  /// The label roles, largest first.
  static List<TextStyle> labelRoles(TextTheme t) =>
      <TextStyle>[t.labelLarge!, t.labelMedium!, t.labelSmall!];

  /// Every role in the scale, grouped by family and ordered largest first within
  /// each family. Lets a test assert the scale is complete and coherent without
  /// restating all fifteen field names.
  static List<List<TextStyle>> families(TextTheme t) => <List<TextStyle>>[
        displayRoles(t),
        headlineRoles(t),
        titleRoles(t),
        bodyRoles(t),
        labelRoles(t),
      ];
}
