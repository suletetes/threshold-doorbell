// Scale integrity for the design tokens (UI/UX audit Phase 1).
//
// A token scale is only worth having if it stays a scale. These tests assert
// each scale is ordered, positive, and in sync with its named constants, so a
// careless edit that inserts 18 between 16 and 20 or duplicates a value fails
// the build instead of quietly making the rhythm uneven again.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/design/tokens.dart';

/// Asserts [values] is strictly increasing.
void expectStrictlyIncreasing(List<num> values, String label) {
  for (var i = 1; i < values.length; i++) {
    expect(
      values[i],
      greaterThan(values[i - 1]),
      reason: '$label must be strictly increasing, but '
          'index $i (${values[i]}) is not greater than index ${i - 1} (${values[i - 1]})',
    );
  }
}

void main() {
  group('Spacing scale (audit section 4, spacing and rhythm)', () {
    test('is strictly increasing', () {
      expectStrictlyIncreasing(Spacing.scale, 'Spacing.scale');
    });

    test('anchors at zero and every other value is positive', () {
      expect(Spacing.scale.first, 0);
      for (final value in Spacing.scale.skip(1)) {
        expect(value, greaterThan(0),
            reason: 'spacing values above the anchor must be positive');
      }
    });

    test('every value above the anchor is a whole multiple of the 4dp step',
        () {
      expect(Spacing.step, 4);
      for (final value in Spacing.scale.skip(1)) {
        expect(
          value % Spacing.step,
          0,
          reason: '$value is not a multiple of the ${Spacing.step}dp step',
        );
      }
    });

    test('the scale list matches the named constants, in order', () {
      expect(Spacing.scale, <double>[
        Spacing.space0,
        Spacing.space1,
        Spacing.space2,
        Spacing.space3,
        Spacing.space4,
        Spacing.space5,
        Spacing.space6,
        Spacing.space7,
        Spacing.space8,
        Spacing.space9,
        Spacing.space10,
      ]);
      expect(Spacing.scale, hasLength(11));
    });
  });

  group('Radius scale (Material 3 shape steps)', () {
    test('is strictly increasing', () {
      expectStrictlyIncreasing(Radii.scale, 'Radii.scale');
    });

    test('anchors at zero and every other value is positive', () {
      expect(Radii.scale.first, 0);
      for (final value in Radii.scale.skip(1)) {
        expect(value, greaterThan(0));
      }
    });

    test('the scale list matches the named constants, in order', () {
      expect(Radii.scale, <double>[
        Radii.none,
        Radii.extraSmall,
        Radii.small,
        Radii.medium,
        Radii.large,
        Radii.extraLarge,
        Radii.full,
      ]);
    });

    test('every BorderRadius helper matches its scale value', () {
      final pairs = <BorderRadius, double>{
        Radii.roundedExtraSmall: Radii.extraSmall,
        Radii.roundedSmall: Radii.small,
        Radii.roundedMedium: Radii.medium,
        Radii.roundedLarge: Radii.large,
        Radii.roundedExtraLarge: Radii.extraLarge,
        Radii.roundedFull: Radii.full,
      };
      pairs.forEach((borderRadius, expected) {
        expect(borderRadius.topLeft.x, expected);
        expect(borderRadius.bottomRight.x, expected);
      });
    });
  });

  group('Elevation scale', () {
    test('is strictly increasing', () {
      expectStrictlyIncreasing(Elevations.scale, 'Elevations.scale');
    });

    test('anchors flat at zero and every other level is positive', () {
      expect(Elevations.scale.first, 0);
      for (final value in Elevations.scale.skip(1)) {
        expect(value, greaterThan(0));
      }
    });

    test('the scale list matches the named constants, in order', () {
      expect(Elevations.scale, <double>[
        Elevations.level0,
        Elevations.level1,
        Elevations.level2,
        Elevations.level3,
        Elevations.level4,
        Elevations.level5,
      ]);
    });
  });

  group('Motion scale', () {
    test('is strictly increasing in milliseconds', () {
      expectStrictlyIncreasing(
        Motion.scale.map((d) => d.inMilliseconds).toList(),
        'Motion.scale',
      );
    });

    test('anchors at zero and every other duration is positive', () {
      expect(Motion.scale.first, Duration.zero);
      for (final duration in Motion.scale.skip(1)) {
        expect(duration.inMicroseconds, greaterThan(0));
      }
    });

    test('the scale list matches the named constants, in order', () {
      expect(Motion.scale, <Duration>[
        Motion.instant,
        Motion.fast,
        Motion.standard,
        Motion.emphasized,
        Motion.slow,
      ]);
    });

    test('no duration is long enough to delay information', () {
      // Motion here is a redundant channel for state change, not decoration.
      for (final duration in Motion.scale) {
        expect(duration.inMilliseconds, lessThanOrEqualTo(500));
      }
    });

    test('a curve is defined for every motion role', () {
      expect(Motion.standardCurve, isA<Curve>());
      expect(Motion.emphasizedCurve, isA<Curve>());
      expect(Motion.enterCurve, isA<Curve>());
      expect(Motion.exitCurve, isA<Curve>());
    });
  });

  group('Touch target tokens (audit section 4, touch targets)', () {
    test('the minimum is the 48dp WCAG and Material floor', () {
      expect(TouchTarget.minimum, 48);
    });

    test('the minimum button size is at least 48dp tall', () {
      expect(TouchTarget.minimumButtonSize.height,
          greaterThanOrEqualTo(TouchTarget.minimum));
      expect(TouchTarget.minimumButtonSize.width, greaterThan(0));
    });
  });

  group('Reduced motion (audit section 4, accessibility gap)', () {
    testWidgets('prefersReducedMotion is false when animations are enabled',
        (tester) async {
      late bool reduced;
      late Duration resolved;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Builder(
            builder: (BuildContext context) {
              reduced = prefersReducedMotion(context);
              resolved = motionDuration(context, Motion.standard);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(reduced, isFalse);
      expect(resolved, Motion.standard);
    });

    testWidgets('prefersReducedMotion is true when disableAnimations is set',
        (tester) async {
      late bool reduced;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (BuildContext context) {
              reduced = prefersReducedMotion(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(reduced, isTrue);
    });

    testWidgets('every duration collapses to zero under reduced motion',
        (tester) async {
      final resolved = <Duration>[];
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (BuildContext context) {
              for (final base in Motion.scale) {
                resolved.add(motionDuration(context, base));
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved, hasLength(Motion.scale.length));
      for (final duration in resolved) {
        expect(duration, Duration.zero);
      }
    });
  });
}
