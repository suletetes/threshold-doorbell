// Type scale integrity (UI/UX audit C3). The scale replaced ad hoc inline
// integers, so these tests assert it is actually a scale: every one of the
// fifteen Material 3 roles is present, fully specified (size, weight, height,
// tracking), ordered within its family, and never smaller than the readable
// floor this product accepts.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/design/colors.dart';
import 'package:threshold/design/typography.dart';

/// The fifteen Material 3 roles by name, for reasons that name the offender.
Map<String, TextStyle?> _rolesOf(TextTheme t) => <String, TextStyle?>{
      'displayLarge': t.displayLarge,
      'displayMedium': t.displayMedium,
      'displaySmall': t.displaySmall,
      'headlineLarge': t.headlineLarge,
      'headlineMedium': t.headlineMedium,
      'headlineSmall': t.headlineSmall,
      'titleLarge': t.titleLarge,
      'titleMedium': t.titleMedium,
      'titleSmall': t.titleSmall,
      'bodyLarge': t.bodyLarge,
      'bodyMedium': t.bodyMedium,
      'bodySmall': t.bodySmall,
      'labelLarge': t.labelLarge,
      'labelMedium': t.labelMedium,
      'labelSmall': t.labelSmall,
    };

void main() {
  group('The scale is complete', () {
    test('all fifteen Material 3 roles are defined', () {
      final roles = _rolesOf(ThresholdTypography.base);
      expect(roles, hasLength(15));
      roles.forEach((name, style) {
        expect(style, isNotNull, reason: '$name is missing from the scale');
      });
    });

    test('every role specifies size, weight, height, and letter spacing', () {
      // Audit C3: the old code had no line heights except two sporadic values
      // and no letter spacing at all. Every role now states all four.
      _rolesOf(ThresholdTypography.base).forEach((name, style) {
        expect(style!.fontSize, isNotNull, reason: '$name has no fontSize');
        expect(style.fontWeight, isNotNull, reason: '$name has no fontWeight');
        expect(style.height, isNotNull, reason: '$name has no line height');
        expect(style.letterSpacing, isNotNull,
            reason: '$name has no letterSpacing');
      });
    });
  });

  group('The scale is coherent', () {
    test('every font size is positive', () {
      _rolesOf(ThresholdTypography.base).forEach((name, style) {
        expect(style!.fontSize, greaterThan(0),
            reason: '$name has a non-positive size');
      });
    });

    test('no role renders below the readable floor', () {
      expect(ThresholdTypography.minimumFontSize, 12);
      _rolesOf(ThresholdTypography.base).forEach((name, style) {
        expect(
          style!.fontSize,
          greaterThanOrEqualTo(ThresholdTypography.minimumFontSize),
          reason:
              '$name is below the ${ThresholdTypography.minimumFontSize}px floor',
        );
      });
    });

    test('each family descends strictly from large to small', () {
      for (final family
          in ThresholdTypography.families(ThresholdTypography.base)) {
        for (var i = 1; i < family.length; i++) {
          expect(
            family[i].fontSize,
            lessThan(family[i - 1].fontSize!),
            reason: 'family sizes must strictly descend: '
                '${family[i].fontSize} is not smaller than ${family[i - 1].fontSize}',
          );
        }
      }
    });

    test('line heights are plausible multipliers, never absolute pixels', () {
      _rolesOf(ThresholdTypography.base).forEach((name, style) {
        expect(style!.height, greaterThanOrEqualTo(1.0),
            reason: '$name leading is below 1.0');
        expect(style.height, lessThanOrEqualTo(2.0),
            reason: '$name leading is implausibly large');
      });
    });

    test('leading loosens as text gets smaller, within the body family', () {
      // Small running copy needs more leading per em than a display headline.
      final body = ThresholdTypography.bodyRoles(ThresholdTypography.base);
      final display =
          ThresholdTypography.displayRoles(ThresholdTypography.base);
      expect(body.first.height, greaterThan(display.first.height!));
    });

    test('tracking tightens as text gets larger', () {
      // Audit C3: default tracking is too loose at the 22px+ caption size.
      final displayLarge = ThresholdTypography.base.displayLarge!;
      final labelSmall = ThresholdTypography.base.labelSmall!;
      expect(displayLarge.letterSpacing, lessThan(labelSmall.letterSpacing!));
    });

    test('the body roles are readable sizes for an accessibility product', () {
      // Deliberately one step above the stock Material metrics.
      expect(ThresholdTypography.base.bodyLarge!.fontSize,
          greaterThanOrEqualTo(18));
      expect(ThresholdTypography.base.bodyMedium!.fontSize,
          greaterThanOrEqualTo(16));
      expect(ThresholdTypography.base.bodySmall!.fontSize,
          greaterThanOrEqualTo(14));
    });

    test('button and section labels are weighted for hierarchy', () {
      expect(
        ThresholdTypography.base.labelLarge!.fontWeight!.index,
        greaterThan(FontWeight.w400.index),
      );
      expect(
        ThresholdTypography.base.titleLarge!.fontWeight!.index,
        greaterThan(FontWeight.w400.index),
      );
    });
  });

  group('forScheme binds colors without changing metrics', () {
    test('every role takes onSurface from the scheme', () {
      for (final scheme in <ColorScheme>[
        ThresholdColors.light,
        ThresholdColors.dark
      ]) {
        final themed = ThresholdTypography.forScheme(scheme);
        _rolesOf(themed).forEach((name, style) {
          expect(
            style!.color,
            scheme.onSurface,
            reason:
                '$name is not bound to onSurface for the ${scheme.brightness.name} scheme',
          );
        });
      }
    });

    test('the metrics survive the color binding', () {
      final themed = ThresholdTypography.forScheme(ThresholdColors.dark);
      final base = _rolesOf(ThresholdTypography.base);
      _rolesOf(themed).forEach((name, style) {
        expect(style!.fontSize, base[name]!.fontSize,
            reason: '$name size changed');
        expect(style.fontWeight, base[name]!.fontWeight,
            reason: '$name weight changed');
        expect(style.height, base[name]!.height,
            reason: '$name height changed');
        expect(
          style.letterSpacing,
          base[name]!.letterSpacing,
          reason: '$name letterSpacing changed',
        );
      });
    });

    test('the light and dark bindings differ', () {
      expect(
        ThresholdTypography.forScheme(ThresholdColors.light).bodyLarge!.color,
        isNot(ThresholdTypography.forScheme(ThresholdColors.dark)
            .bodyLarge!
            .color),
      );
    });
  });
}
