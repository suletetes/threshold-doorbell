// WCAG 2.2 contrast enforcement (Task 24, FR-10.2, NFR-2; AT-9). The resident can
// adjust caption text size and contrast, but no user setting may breach the
// 4.5:1 minimum contrast floor (FR-10.2, NFR-2) [R-12]. This is pure logic:
// WCAG relative luminance, the contrast ratio, and a function that adjusts a
// foreground color against a background until the ratio meets the floor, so the
// floor is enforced in code and asserted by unit tests without a device.

import 'dart:math' as math;
import 'package:flutter/painting.dart';

/// The WCAG 2.2 AA minimum contrast ratio for normal text (FR-10.2, NFR-2).
const double kContrastFloor = 4.5;

/// WCAG relative luminance of an sRGB [color] (0.0 black .. 1.0 white).
double relativeLuminance(Color color) {
  double channel(double c) {
    final s = c; // already 0..1
    return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = channel(_component(color.r));
  final g = channel(_component(color.g));
  final b = channel(_component(color.b));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

// Color components in this Flutter version are already normalized doubles 0..1.
double _component(double v) => v.clamp(0.0, 1.0);

/// WCAG contrast ratio between two colors, in [1, 21].
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

/// True when [foreground] on [background] meets the 4.5:1 floor (FR-10.2).
bool meetsContrastFloor(Color foreground, Color background) =>
    contrastRatio(foreground, background) >= kContrastFloor - 1e-9;

/// Enforce the contrast floor (FR-10.2, NFR-2). Returns [foreground] unchanged
/// when it already meets the floor; otherwise nudges it toward pure black or
/// pure white (whichever direction gains contrast against [background]) until
/// the floor is met. This guarantees no user contrast setting can breach NFR-2:
/// the returned color always meets the floor.
Color enforceContrastFloor(Color foreground, Color background) {
  if (meetsContrastFloor(foreground, background)) return foreground;
  // Choose the extreme that has the higher contrast with the background.
  final towardBlack = contrastRatio(const Color(0xFF000000), background);
  final towardWhite = contrastRatio(const Color(0xFFFFFFFF), background);
  final target = towardWhite >= towardBlack
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF000000);
  // Binary-search the blend factor toward the target that meets the floor.
  double lo = 0.0;
  double hi = 1.0;
  Color best = target; // target extreme always meets the floor if achievable
  for (var i = 0; i < 24; i++) {
    final mid = (lo + hi) / 2;
    final candidate = Color.lerp(foreground, target, mid)!;
    if (meetsContrastFloor(candidate, background)) {
      best = candidate;
      hi = mid; // try to keep more of the original color
    } else {
      lo = mid;
    }
  }
  return best;
}
