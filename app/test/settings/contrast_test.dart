import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/settings/contrast.dart';

void main() {
  group('WCAG contrast (Task 24, FR-10.2, NFR-2; AT-9)', () {
    test('black on white is the maximum 21:1', () {
      final r = contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF));
      expect(r, closeTo(21.0, 0.1));
    });

    test('white on white is the minimum 1:1', () {
      final r = contrastRatio(const Color(0xFFFFFFFF), const Color(0xFFFFFFFF));
      expect(r, closeTo(1.0, 0.001));
    });

    test('meetsContrastFloor is true at or above 4.5:1, false below', () {
      // A mid grey on white is below the floor.
      expect(
          meetsContrastFloor(const Color(0xFF999999), const Color(0xFFFFFFFF)),
          isFalse);
      // Dark grey on white is above.
      expect(
          meetsContrastFloor(const Color(0xFF595959), const Color(0xFFFFFFFF)),
          isTrue);
    });

    test('enforceContrastFloor keeps a compliant color unchanged', () {
      const fg = Color(0xFF000000);
      const bg = Color(0xFFFFFFFF);
      expect(enforceContrastFloor(fg, bg), fg);
    });

    test('enforceContrastFloor raises a non-compliant color to meet the floor',
        () {
      // Light grey on white breaches the floor; enforcement must fix it.
      const fg = Color(0xFFBBBBBB);
      const bg = Color(0xFFFFFFFF);
      final fixed = enforceContrastFloor(fg, bg);
      expect(meetsContrastFloor(fixed, bg), isTrue);
    });

    test('enforcement works against a dark background too (nudges to white)',
        () {
      const fg = Color(0xFF333333); // dark grey on near-black: too low
      const bg = Color(0xFF000000);
      final fixed = enforceContrastFloor(fg, bg);
      expect(meetsContrastFloor(fixed, bg), isTrue);
    });
  });
}
