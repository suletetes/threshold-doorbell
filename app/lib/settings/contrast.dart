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

/// The opaque color actually seen when [foreground] (which may be translucent)
/// is painted over the opaque [background] (HIGH-07). The relative-luminance
/// formula assumes opaque colors; a translucent foreground must be composited
/// first or its contrast is overstated. [background] is treated as opaque (its
/// own alpha is ignored for compositing, since it is the base layer).
Color compositeOver(Color foreground, Color background) =>
    Color.alphaBlend(foreground, background.withValues(alpha: 1.0));

/// WCAG contrast ratio of a possibly translucent [foreground] against the
/// opaque [background], computed on the composited color (HIGH-07). This is the
/// ratio the resident actually perceives; computing it on the raw foreground
/// ignores the alpha and overstates the contrast (the audit measured a claimed
/// 21:1 that was really 2.36:1 for a translucent case).
double effectiveContrastRatio(Color foreground, Color background) =>
    contrastRatio(compositeOver(foreground, background), background);

/// True when a possibly translucent [foreground] meets the 4.5:1 floor against
/// the opaque [background] once composited (HIGH-07).
bool meetsContrastFloorComposited(Color foreground, Color background) =>
    effectiveContrastRatio(foreground, background) >= kContrastFloor - 1e-9;

/// Whether [color] is fully opaque. Caption backgrounds must be opaque so the
/// contrast floor is computed against a stable composite rather than against
/// whatever inbound video shows through (HIGH-07).
bool isOpaque(Color color) => color.a >= 1.0 - 1e-9;

/// Force [color] to be fully opaque (alpha 1.0), rejecting a translucent caption
/// background (HIGH-07). A translucent background lets arbitrary video bleed
/// through the surface the floor was computed against, so it is not allowed.
Color forceOpaque(Color color) => color.withValues(alpha: 1.0);

/// A de-emphasized caption color that both reads as de-emphasized (reduced
/// alpha, so provisional/low-confidence text is visibly softer, AT-4) AND meets
/// the 4.5:1 floor once composited over the opaque [background] (HIGH-07).
///
/// Starts from [foreground] at [targetAlpha] (0.6 by default). If the composited
/// result already meets the floor it is returned unchanged. Otherwise the alpha
/// is raised toward 1.0 only as far as needed to reach the floor, so the text
/// stays as de-emphasized as the floor permits. If even full alpha does not meet
/// the floor (a near-illegible foreground on this background), the opaque
/// floor-enforced foreground is returned so the floor is never breached.
Color deEmphasizedCaptionColor(
  Color foreground,
  Color background, {
  double targetAlpha = 0.6,
}) {
  Color atAlpha(double a) =>
      compositeOver(foreground.withValues(alpha: a), background);
  if (meetsContrastFloor(atAlpha(targetAlpha), background)) {
    return foreground.withValues(alpha: targetAlpha);
  }
  // Binary-search the smallest alpha in [targetAlpha, 1.0] that meets the floor.
  double lo = targetAlpha;
  double hi = 1.0;
  if (!meetsContrastFloor(atAlpha(hi), background)) {
    // Even opaque does not meet the floor on this background: fall back to the
    // floor-enforced opaque foreground so the floor still holds.
    return enforceContrastFloor(forceOpaque(foreground), background);
  }
  for (var i = 0; i < 24; i++) {
    final mid = (lo + hi) / 2;
    if (meetsContrastFloor(atAlpha(mid), background)) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  return foreground.withValues(alpha: hi);
}

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
