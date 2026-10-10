// HIGH-07 (probe P4): caption contrast must meet the 4.5:1 floor at EVERY
// emphasis level, including the de-emphasized provisional / low-confidence text,
// and translucent caption backgrounds must be rejected.
//
// The audit measured the enforced foreground at 4.50:1 but the provisional text
// (the same color at 0.6 alpha) at 2.21:1, and a translucent background that
// claimed 21:1 but was really 2.36:1. These tests pin both: the de-emphasized
// color meets the floor against the opaque background, and a translucent
// background is forced opaque so the floor is computed against a stable base.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/settings/contrast.dart';
import 'package:threshold/settings/settings_state.dart';

void main() {
  group('Alpha-aware contrast (HIGH-07)', () {
    test('effectiveContrastRatio accounts for a translucent foreground', () {
      // Black text at 0.6 alpha over white is really dark grey, not pure black.
      final raw = contrastRatio(
        const Color(0x99000000), // this ignores alpha in the naive formula
        const Color(0xFFFFFFFF),
      );
      final effective = effectiveContrastRatio(
        const Color(0x99000000),
        const Color(0xFFFFFFFF),
      );
      // The effective ratio is lower than the naive ratio because the composite
      // is lighter than pure black.
      expect(effective, lessThan(raw));
    });

    test('a translucent background is forced opaque', () {
      final s = ThresholdSettings.defaults().copyWith(
        captionBackground: const Color(0x80123456), // 50% alpha
      );
      expect(isOpaque(s.captionBackground), isTrue,
          reason: 'caption background must be opaque (HIGH-07)');
    });
  });

  group('De-emphasized caption color meets the floor at every emphasis (HIGH-07, P4)',
      () {
    // Reproduce the probe P4 foreground: a mid-grey that passes at full alpha
    // but failed at 0.6 alpha before the fix.
    const List<Color> foregrounds = <Color>[
      Color(0xFFFFFFFF), // white
      Color(0xFF747474), // the mid-grey from probe P4
      Color(0xFFBBBBBB),
    ];
    const Color background = Color(0xFF000000);

    for (final fg in foregrounds) {
      test('fg ${fg.toARGB32().toRadixString(16)}: emphasized AND de-emphasized meet 4.5:1',
          () {
        // The enforced foreground (emphasized / normal) meets the floor.
        final enforced = enforceContrastFloor(fg, background);
        expect(meetsContrastFloor(enforced, background), isTrue);

        // The de-emphasized color (provisional + low confidence) meets the floor
        // against the opaque background once composited (this is what P4 failed).
        final deEmph = deEmphasizedCaptionColor(fg, background);
        expect(
          meetsContrastFloorComposited(deEmph, background),
          isTrue,
          reason: 'de-emphasized text must meet 4.5:1 (HIGH-07, P4)',
        );
      });
    }

    test('the de-emphasized color stays softer than full alpha when it can', () {
      // White on black: 0.6 alpha already clears the floor, so the softer alpha
      // is preserved (AT-4 keeps provisional text visibly de-emphasized).
      final deEmph = deEmphasizedCaptionColor(
        const Color(0xFFFFFFFF),
        const Color(0xFF000000),
      );
      expect(deEmph.a, lessThan(1.0));
    });

    test('a near-illegible foreground is raised until it meets the floor', () {
      // A foreground close to the background cannot be de-emphasized below the
      // floor: the result still meets it (never breaches NFR-2).
      final deEmph = deEmphasizedCaptionColor(
        const Color(0xFF111111),
        const Color(0xFF000000),
      );
      expect(meetsContrastFloorComposited(deEmph, const Color(0xFF000000)), isTrue);
    });
  });
}
