// WCAG relative luminance and contrast ratio, computed here in the test tree on
// purpose.
//
// The app already enforces a 4.5:1 floor on the caption path through
// lib/settings/contrast.dart. These design tests deliberately do NOT import that
// helper: if the production implementation ever drifts, a test that reuses it
// would drift with it and still pass. This is an independent implementation of
// the WCAG 2.2 formula, so the two have to agree for the suite to be green.
//
// Formula: WCAG 2.2, Understanding SC 1.4.3.
//   L = 0.2126 R + 0.7152 G + 0.0722 B, where each channel c (0..1) is
//   c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ^ 2.4
//   ratio = (Llighter + 0.05) / (Ldarker + 0.05), in [1, 21]

import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// The WCAG 2.2 AA minimum contrast ratio for normal text.
const double kAaNormalText = 4.5;

double _linearize(double channel) {
  final c = channel.clamp(0.0, 1.0);
  return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

/// WCAG relative luminance of [color], 0.0 for black and 1.0 for white.
double wcagRelativeLuminance(Color color) {
  return 0.2126 * _linearize(color.r) +
      0.7152 * _linearize(color.g) +
      0.0722 * _linearize(color.b);
}

/// WCAG contrast ratio between [a] and [b], in the range 1.0 to 21.0.
double wcagContrastRatio(Color a, Color b) {
  final la = wcagRelativeLuminance(a);
  final lb = wcagRelativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}
