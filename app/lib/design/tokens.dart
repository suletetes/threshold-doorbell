// Design tokens for Threshold (UI/UX audit, Phase 1). The single source of
// truth for every spacing, radius, elevation, and motion value in the app.
//
// Design principle 1 from the audit: no literal in a screen. A raw padding, a
// raw radius, a raw duration, or a raw font size in a widget file is a defect.
// Everything a screen needs comes from here or from the ThemeData built in
// `theme.dart`.
//
// The scales are exposed twice on purpose: as named constants for call sites,
// and as an ordered `scale` list so the test suite can assert the scale is
// internally coherent (positive, strictly increasing, and in sync with the
// named constants). That is what keeps a token scale from rotting into an
// arbitrary bag of numbers.

import 'package:flutter/material.dart';

/// Spacing scale, 4dp based (audit section 4, "Spacing, rhythm, density").
///
/// The existing screens used 8, 12, 16, 20, and 24 near a 4dp grid but not
/// derived from one, which is why the vertical rhythm reads uneven. These are
/// the only spacing values the app may use.
abstract final class Spacing {
  /// The zero anchor of the scale. Used where a gap must be explicitly absent.
  static const double space0 = 0;
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space7 = 32;
  static const double space8 = 40;
  static const double space9 = 48;
  static const double space10 = 64;

  /// The scale in ascending order, for scale integrity tests.
  static const List<double> scale = <double>[
    space0,
    space1,
    space2,
    space3,
    space4,
    space5,
    space6,
    space7,
    space8,
    space9,
    space10,
  ];

  /// The step the scale is built on. Every value above the zero anchor is a
  /// whole multiple of this.
  static const double step = 4;
}

/// Corner radius scale, aligned to the Material 3 shape steps (audit section 4,
/// "Radius, shadow, elevation, depth").
abstract final class Radii {
  static const double none = 0;
  static const double extraSmall = 4;
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
  static const double extraLarge = 28;

  /// A pill. Large enough to fully round any control this app ships; kept as a
  /// number rather than a StadiumBorder so it composes with BorderRadius.
  static const double full = 999;

  /// The scale in ascending order, for scale integrity tests.
  static const List<double> scale = <double>[
    none,
    extraSmall,
    small,
    medium,
    large,
    extraLarge,
    full,
  ];

  static const BorderRadius roundedExtraSmall =
      BorderRadius.all(Radius.circular(extraSmall));
  static const BorderRadius roundedSmall =
      BorderRadius.all(Radius.circular(small));
  static const BorderRadius roundedMedium =
      BorderRadius.all(Radius.circular(medium));
  static const BorderRadius roundedLarge =
      BorderRadius.all(Radius.circular(large));
  static const BorderRadius roundedExtraLarge =
      BorderRadius.all(Radius.circular(extraLarge));
  static const BorderRadius roundedFull =
      BorderRadius.all(Radius.circular(full));
}

/// Elevation scale, the Material 3 tonal elevation levels (audit section 4: the
/// app previously had no elevation system, only a raw scrim and default Card).
abstract final class Elevations {
  /// Flat on the surface. The default for most content.
  static const double level0 = 0;
  static const double level1 = 1;
  static const double level2 = 3;
  static const double level3 = 6;
  static const double level4 = 8;
  static const double level5 = 12;

  /// The scale in ascending order, for scale integrity tests.
  static const List<double> scale = <double>[
    level0,
    level1,
    level2,
    level3,
    level4,
    level5
  ];
}

/// Motion tokens (audit C6: the app currently has zero motion, and any motion
/// added must be gated on reduced motion).
///
/// Durations are deliberately short. This is a product where motion carries
/// state meaning for someone who gets no audio cue, so a transition has to be
/// perceptible without ever delaying information.
abstract final class Motion {
  /// No animation. What every duration collapses to under reduced motion.
  static const Duration instant = Duration.zero;

  /// Press feedback, ripples, small color changes.
  static const Duration fast = Duration(milliseconds: 120);

  /// The default: cross fades, panel swaps, caption entry.
  static const Duration standard = Duration(milliseconds: 220);

  /// A state change the user must not miss, for example session state.
  static const Duration emphasized = Duration(milliseconds: 320);

  /// Full screen or large surface transitions only.
  static const Duration slow = Duration(milliseconds: 480);

  /// The duration scale in ascending order, for scale integrity tests.
  static const List<Duration> scale = <Duration>[
    instant,
    fast,
    standard,
    emphasized,
    slow
  ];

  /// The default easing for a change that both enters and exits.
  static const Curve standardCurve = Curves.easeInOutCubic;

  /// Emphasized easing, for a state change that must draw the eye.
  static const Curve emphasizedCurve = Curves.easeInOutCubicEmphasized;

  /// Decelerating easing, for content arriving on screen.
  static const Curve enterCurve = Curves.easeOutCubic;

  /// Accelerating easing, for content leaving the screen.
  static const Curve exitCurve = Curves.easeInCubic;
}

/// Touch target tokens (audit section 4, "Touch targets and gestures": nothing
/// in the codebase asserted a 48dp minimum).
abstract final class TouchTarget {
  /// The WCAG 2.2 AA / Material minimum interactive dimension in dp.
  static const double minimum = 48;

  /// The minimum size applied to every button theme. The width floor keeps a
  /// short label ("OK") from collapsing to a sliver.
  static const Size minimumButtonSize = Size(64, minimum);
}

/// True when the platform asks for reduced motion (audit section 4,
/// "Accessibility": `MediaQuery.disableAnimations` was unhandled).
///
/// This is the single place the app reads that preference. Every animated
/// surface goes through here or through [motionDuration].
bool prefersReducedMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);

/// [base] normally, or [Motion.instant] when the platform asks for reduced
/// motion. Wrap every animation duration in this so a reduced-motion user gets
/// the end state immediately instead of a shortened animation.
Duration motionDuration(BuildContext context, Duration base) =>
    prefersReducedMotion(context) ? Motion.instant : base;
