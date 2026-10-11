// Color scheme and semantic role tests (UI/UX audit C1, C2, and design
// principle 7: "both schemes are designed and tested, not derived by accident").
//
// The contrast assertions are the point of this file. The app enforced a 4.5:1
// floor on the caption path only; everywhere else color was an unnamed literal
// chosen by eye, so contrast was unverified. These tests put the rest of the
// palette under the same floor, in both schemes, using an independent WCAG
// implementation (see contrast_math.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/design/colors.dart';

import 'contrast_math.dart';

/// The two schemes, paired with their semantic roles, so every assertion runs
/// against both without duplication.
const Map<String, (ColorScheme, ThresholdSemanticColors)> _schemes =
    <String, (ColorScheme, ThresholdSemanticColors)>{
  'light': (ThresholdColors.light, ThresholdSemanticColors.light),
  'dark': (ThresholdColors.dark, ThresholdSemanticColors.dark),
};

void _expectMeetsAa(Color foreground, Color background, String what) {
  final ratio = wcagContrastRatio(foreground, background);
  expect(
    ratio,
    greaterThanOrEqualTo(kAaNormalText),
    reason: '$what is ${ratio.toStringAsFixed(2)}:1, '
        'below the $kAaNormalText:1 WCAG 2.2 AA floor for normal text',
  );
}

void main() {
  group('ColorScheme brightness', () {
    test('the light scheme is light and the dark scheme is dark', () {
      expect(ThresholdColors.light.brightness, Brightness.light);
      expect(ThresholdColors.dark.brightness, Brightness.dark);
    });

    test(
        'the two schemes are genuinely different, not one derived from the other',
        () {
      expect(
          ThresholdColors.light.surface, isNot(ThresholdColors.dark.surface));
      expect(
          ThresholdColors.light.primary, isNot(ThresholdColors.dark.primary));
      expect(ThresholdColors.light.onSurface,
          isNot(ThresholdColors.dark.onSurface));
    });

    test('the light surface really is lighter than the dark surface', () {
      expect(
        wcagRelativeLuminance(ThresholdColors.light.surface),
        greaterThan(wcagRelativeLuminance(ThresholdColors.dark.surface)),
      );
    });

    test('every color in both schemes is fully opaque', () {
      // A translucent scheme color makes contrast unprovable, because the real
      // rendered color then depends on whatever happens to be behind it.
      for (final entry in _schemes.entries) {
        final scheme = entry.value.$1;
        final colors = <String, Color>{
          'primary': scheme.primary,
          'onPrimary': scheme.onPrimary,
          'surface': scheme.surface,
          'onSurface': scheme.onSurface,
          'onSurfaceVariant': scheme.onSurfaceVariant,
          'error': scheme.error,
          'onError': scheme.onError,
          'outline': scheme.outline,
        };
        colors.forEach((name, color) {
          expect(color.a, 1.0, reason: '${entry.key} $name must be opaque');
        });
      }
    });
  });

  group('Scheme contrast meets WCAG 2.2 AA (4.5:1) in both schemes', () {
    for (final entry in _schemes.entries) {
      final name = entry.key;
      final scheme = entry.value.$1;

      test('$name: body text (onSurface on surface)', () {
        _expectMeetsAa(
            scheme.onSurface, scheme.surface, '$name onSurface on surface');
      });

      test('$name: secondary body text (onSurfaceVariant on surface)', () {
        _expectMeetsAa(
          scheme.onSurfaceVariant,
          scheme.surface,
          '$name onSurfaceVariant on surface',
        );
      });

      test('$name: primary button label (onPrimary on primary)', () {
        _expectMeetsAa(
            scheme.onPrimary, scheme.primary, '$name onPrimary on primary');
      });

      test('$name: error text (onError on error)', () {
        _expectMeetsAa(scheme.onError, scheme.error, '$name onError on error');
      });

      test('$name: container labels', () {
        _expectMeetsAa(
          scheme.onPrimaryContainer,
          scheme.primaryContainer,
          '$name onPrimaryContainer on primaryContainer',
        );
        _expectMeetsAa(
          scheme.onSecondaryContainer,
          scheme.secondaryContainer,
          '$name onSecondaryContainer on secondaryContainer',
        );
        _expectMeetsAa(
          scheme.onErrorContainer,
          scheme.errorContainer,
          '$name onErrorContainer on errorContainer',
        );
      });

      test('$name: snack bar text (onInverseSurface on inverseSurface)', () {
        _expectMeetsAa(
          scheme.onInverseSurface,
          scheme.inverseSurface,
          '$name onInverseSurface on inverseSurface',
        );
      });

      test('$name: body text on every surface container tone', () {
        final containers = <String, Color>{
          'surfaceContainerLowest': scheme.surfaceContainerLowest,
          'surfaceContainerLow': scheme.surfaceContainerLow,
          'surfaceContainer': scheme.surfaceContainer,
          'surfaceContainerHigh': scheme.surfaceContainerHigh,
          'surfaceContainerHighest': scheme.surfaceContainerHighest,
        };
        containers.forEach((container, color) {
          _expectMeetsAa(
              scheme.onSurface, color, '$name onSurface on $container');
        });
      });
    }
  });

  group('ThresholdSemanticColors roles', () {
    test('both schemes expose all eight semantic roles', () {
      for (final entry in _schemes.entries) {
        final semantic = entry.value.$2;
        expect(semantic.all, hasLength(8),
            reason: '${entry.key} must expose eight roles');
        for (final color in semantic.all) {
          expect(color.a, 1.0,
              reason: '${entry.key} semantic roles must be opaque');
        }
      }
    });

    test('the light and dark role sets are distinct', () {
      expect(
          ThresholdSemanticColors.light, isNot(ThresholdSemanticColors.dark));
      expect(ThresholdSemanticColors.light.captionSurface,
          isNot(ThresholdSemanticColors.dark.captionSurface));
      expect(ThresholdSemanticColors.light.live,
          isNot(ThresholdSemanticColors.dark.live));
      expect(ThresholdSemanticColors.light.danger,
          isNot(ThresholdSemanticColors.dark.danger));
    });

    test('recording and danger are distinguishable roles, not the same color',
        () {
      expect(
        ThresholdSemanticColors.light.recording,
        isNot(ThresholdSemanticColors.light.danger),
      );
      expect(
        ThresholdSemanticColors.dark.recording,
        isNot(ThresholdSemanticColors.dark.danger),
      );
    });
  });

  group('Semantic role contrast (FR-10.2, NFR-2 discipline applied app wide)',
      () {
    for (final entry in _schemes.entries) {
      final name = entry.key;
      final scheme = entry.value.$1;
      final semantic = entry.value.$2;

      test('$name: confident caption text on the caption surface', () {
        _expectMeetsAa(
          semantic.captionOnSurface,
          semantic.captionSurface,
          '$name captionOnSurface on captionSurface',
        );
      });

      test('$name: provisional caption text is still readable, not just faded',
          () {
        // Audit C7: provisional text must be a deliberate treatment, which means
        // it still has to clear the floor. Reduced emphasis is not permission to
        // drop below 4.5:1.
        _expectMeetsAa(
          semantic.captionProvisional,
          semantic.captionSurface,
          '$name captionProvisional on captionSurface',
        );
      });

      test('$name: provisional reads as lower emphasis than confident text',
          () {
        final confident = wcagContrastRatio(
            semantic.captionOnSurface, semantic.captionSurface);
        final provisional = wcagContrastRatio(
          semantic.captionProvisional,
          semantic.captionSurface,
        );
        expect(provisional, lessThan(confident));
      });

      test('$name: status roles carry text on the scheme surface', () {
        final roles = <String, Color>{
          'live': semantic.live,
          'recording': semantic.recording,
          'success': semantic.success,
          'warning': semantic.warning,
          'danger': semantic.danger,
        };
        roles.forEach((role, color) {
          _expectMeetsAa(color, scheme.surface, '$name $role on surface');
        });
      });
    }
  });

  group('ThresholdSemanticColors.copyWith', () {
    test('replaces only the roles it is given', () {
      const original = ThresholdSemanticColors.light;
      const replacement = Color(0xFF123456);
      final updated = original.copyWith(live: replacement);

      expect(updated.live, replacement);
      expect(updated.captionSurface, original.captionSurface);
      expect(updated.captionOnSurface, original.captionOnSurface);
      expect(updated.captionProvisional, original.captionProvisional);
      expect(updated.recording, original.recording);
      expect(updated.success, original.success);
      expect(updated.warning, original.warning);
      expect(updated.danger, original.danger);
    });

    test('with no arguments returns an equal value', () {
      const original = ThresholdSemanticColors.light;
      expect(original.copyWith(), original);
    });

    test('can replace every role at once', () {
      const replacement = Color(0xFF00FF00);
      final updated = ThresholdSemanticColors.light.copyWith(
        captionSurface: replacement,
        captionOnSurface: replacement,
        captionProvisional: replacement,
        live: replacement,
        recording: replacement,
        success: replacement,
        warning: replacement,
        danger: replacement,
      );
      expect(updated.all, everyElement(replacement));
    });
  });

  group('ThresholdSemanticColors.lerp', () {
    test('t = 0 returns the start value', () {
      final result =
          ThresholdSemanticColors.light.lerp(ThresholdSemanticColors.dark, 0);
      expect(result, ThresholdSemanticColors.light);
    });

    test('t = 1 returns the end value', () {
      final result =
          ThresholdSemanticColors.light.lerp(ThresholdSemanticColors.dark, 1);
      expect(result, ThresholdSemanticColors.dark);
    });

    test('t = 0.5 lands between the two, per role', () {
      final result =
          ThresholdSemanticColors.light.lerp(ThresholdSemanticColors.dark, 0.5);
      expect(
        result.live,
        Color.lerp(ThresholdSemanticColors.light.live,
            ThresholdSemanticColors.dark.live, 0.5),
      );
      expect(
        result.danger,
        Color.lerp(ThresholdSemanticColors.light.danger,
            ThresholdSemanticColors.dark.danger, 0.5),
      );
      expect(result, isNot(ThresholdSemanticColors.light));
      expect(result, isNot(ThresholdSemanticColors.dark));
    });

    test('a null or foreign other returns this unchanged', () {
      expect(ThresholdSemanticColors.light.lerp(null, 0.5),
          ThresholdSemanticColors.light);
    });

    test('every role is interpolated, none is dropped', () {
      final result = ThresholdSemanticColors.light
          .lerp(ThresholdSemanticColors.dark, 0.25);
      for (var i = 0; i < result.all.length; i++) {
        expect(
          result.all[i],
          Color.lerp(
            ThresholdSemanticColors.light.all[i],
            ThresholdSemanticColors.dark.all[i],
            0.25,
          ),
        );
      }
    });
  });

  group('Value equality', () {
    test('identical role sets are equal and hash alike', () {
      const a = ThresholdSemanticColors.light;
      final b = ThresholdSemanticColors.light.copyWith();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a single differing role breaks equality', () {
      const a = ThresholdSemanticColors.light;
      final b = a.copyWith(warning: const Color(0xFF010203));
      expect(a, isNot(b));
    });
  });

  group('Brand seed', () {
    test('the light primary is the brand blue itself', () {
      expect(ThresholdColors.light.primary, kThresholdBrandSeed);
    });

    test('the brand blue carries white text at AA', () {
      _expectMeetsAa(const Color(0xFFFFFFFF), kThresholdBrandSeed,
          'white on the brand blue');
    });
  });
}
