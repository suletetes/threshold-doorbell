// Sanity checks on the test tree's own WCAG implementation. If the helper the
// contrast assertions depend on were wrong, every contrast test would be
// meaningless, so the helper is verified against the values WCAG 2.2 fixes by
// definition.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast_math.dart';

void main() {
  group('WCAG relative luminance', () {
    test('black is 0 and white is 1', () {
      expect(wcagRelativeLuminance(const Color(0xFF000000)), closeTo(0.0, 1e-9));
      expect(wcagRelativeLuminance(const Color(0xFFFFFFFF)), closeTo(1.0, 1e-9));
    });

    test('is monotonic along the grey ramp', () {
      var previous = -1.0;
      for (final value in <int>[0x00, 0x20, 0x40, 0x60, 0x80, 0xA0, 0xC0, 0xE0, 0xFF]) {
        final grey = Color.fromARGB(0xFF, value, value, value);
        final luminance = wcagRelativeLuminance(grey);
        expect(luminance, greaterThan(previous));
        previous = luminance;
      }
    });
  });

  group('WCAG contrast ratio', () {
    test('black on white is the 21:1 maximum', () {
      expect(
        wcagContrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21.0, 1e-6),
      );
    });

    test('a color against itself is the 1:1 minimum', () {
      expect(
        wcagContrastRatio(const Color(0xFF1565C0), const Color(0xFF1565C0)),
        closeTo(1.0, 1e-9),
      );
    });

    test('is symmetric in its arguments', () {
      const a = Color(0xFF1565C0);
      const b = Color(0xFFF9F9FF);
      expect(wcagContrastRatio(a, b), closeTo(wcagContrastRatio(b, a), 1e-12));
    });

    test('reproduces a known published pair', () {
      // #777777 on #FFFFFF is the canonical WCAG borderline example at 4.48:1,
      // which is why 0x777777 fails AA for normal text by a hair.
      final ratio = wcagContrastRatio(const Color(0xFF777777), const Color(0xFFFFFFFF));
      expect(ratio, closeTo(4.48, 0.02));
      expect(ratio, lessThan(kAaNormalText));
    });
  });
}
