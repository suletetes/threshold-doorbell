// ThemeData factory tests (UI/UX audit C1, section 3.1).
//
// The audit's point about component themes is that they lift every screen at
// once precisely because the screens currently fall back to stock defaults. So
// these tests assert the component themes are actually there, that the semantic
// extension is registered on both themes (otherwise every
// ThresholdSemanticColors.of call silently falls back), and that the button
// themes really do enforce the 48dp target the audit found nothing asserting.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/design/colors.dart';
import 'package:threshold/design/theme.dart';
import 'package:threshold/design/tokens.dart';
import 'package:threshold/design/typography.dart';

Map<String, ThemeData> _themes() => <String, ThemeData>{
      'light': ThresholdTheme.light(),
      'dark': ThresholdTheme.dark(),
    };

void main() {
  group('Both themes build', () {
    test('light() and dark() build without throwing', () {
      expect(ThresholdTheme.light, returnsNormally);
      expect(ThresholdTheme.dark, returnsNormally);
    });

    test('both use Material 3', () {
      _themes().forEach((name, theme) {
        expect(theme.useMaterial3, isTrue, reason: '$name is not Material 3');
      });
    });

    test('each theme carries the matching brightness and scheme', () {
      final light = ThresholdTheme.light();
      final dark = ThresholdTheme.dark();
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.colorScheme, ThresholdColors.light);
      expect(dark.colorScheme, ThresholdColors.dark);
    });

    test('the scaffold background follows the scheme surface', () {
      _themes().forEach((name, theme) {
        expect(theme.scaffoldBackgroundColor, theme.colorScheme.surface, reason: name);
      });
    });

    test('the text theme is the app type scale, not stock Material', () {
      _themes().forEach((name, theme) {
        expect(
          theme.textTheme.bodyLarge!.fontSize,
          ThresholdTypography.base.bodyLarge!.fontSize,
          reason: '$name bodyLarge is not from the app scale',
        );
        expect(theme.textTheme.bodyLarge!.height, isNotNull, reason: '$name has no leading');
        expect(theme.textTheme.bodyLarge!.color, theme.colorScheme.onSurface, reason: name);
      });
    });
  });

  group('The semantic extension is registered', () {
    test('both themes expose ThresholdSemanticColors', () {
      _themes().forEach((name, theme) {
        final semantic = theme.extension<ThresholdSemanticColors>();
        expect(semantic, isNotNull, reason: '$name does not register the extension');
        expect(semantic!.all, hasLength(8), reason: '$name is missing semantic roles');
      });
    });

    test('each theme registers the role set that matches its brightness', () {
      expect(
        ThresholdTheme.light().extension<ThresholdSemanticColors>(),
        ThresholdSemanticColors.light,
      );
      expect(
        ThresholdTheme.dark().extension<ThresholdSemanticColors>(),
        ThresholdSemanticColors.dark,
      );
    });

    testWidgets('ThresholdSemanticColors.of reads the registered extension', (tester) async {
      late ThresholdSemanticColors resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThresholdTheme.dark(),
          home: Builder(
            builder: (BuildContext context) {
              resolved = ThresholdSemanticColors.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved, ThresholdSemanticColors.dark);
    });

    testWidgets('of() falls back by brightness when no extension is registered', (tester) async {
      late ThresholdSemanticColors resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Builder(
            builder: (BuildContext context) {
              resolved = ThresholdSemanticColors.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved, ThresholdSemanticColors.dark);
    });

    testWidgets('the extension interpolates across a theme change', (tester) async {
      // ThemeData.lerp routes through the extension's lerp, so a theme animation
      // must not drop the semantic roles halfway through.
      final mid = ThemeData.lerp(ThresholdTheme.light(), ThresholdTheme.dark(), 0.5);
      final semantic = mid.extension<ThresholdSemanticColors>();
      expect(semantic, isNotNull);
      expect(semantic!.all, hasLength(8));
      expect(semantic, isNot(ThresholdSemanticColors.light));
      expect(semantic, isNot(ThresholdSemanticColors.dark));
    });
  });

  group('Button themes enforce the 48dp minimum target', () {
    test('all three button themes are defined with a 48dp floor', () {
      _themes().forEach((name, theme) {
        final styles = <String, ButtonStyle?>{
          'filledButton': theme.filledButtonTheme.style,
          'outlinedButton': theme.outlinedButtonTheme.style,
          'textButton': theme.textButtonTheme.style,
        };
        styles.forEach((which, style) {
          expect(style, isNotNull, reason: '$name $which has no style');
          final minimumSize = style!.minimumSize?.resolve(<WidgetState>{});
          expect(minimumSize, isNotNull, reason: '$name $which has no minimumSize');
          expect(
            minimumSize!.height,
            greaterThanOrEqualTo(TouchTarget.minimum),
            reason: '$name $which is below the ${TouchTarget.minimum}dp target',
          );
          expect(
            style.tapTargetSize,
            MaterialTapTargetSize.padded,
            reason: '$name $which does not pad its tap target',
          );
        });
      });
    });

    testWidgets('a rendered FilledButton is at least 48dp tall', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThresholdTheme.light(),
          home: Scaffold(
            body: Center(
              child: FilledButton(onPressed: () {}, child: const Text('OK')),
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byType(FilledButton));
      expect(size.height, greaterThanOrEqualTo(TouchTarget.minimum));
      expect(size.width, greaterThanOrEqualTo(TouchTarget.minimumButtonSize.width));
    });

    testWidgets('a rendered OutlinedButton is at least 48dp tall', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThresholdTheme.dark(),
          home: Scaffold(
            body: Center(
              child: OutlinedButton(onPressed: () {}, child: const Text('OK')),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(OutlinedButton)).height,
        greaterThanOrEqualTo(TouchTarget.minimum),
      );
    });

    testWidgets('a rendered TextButton is at least 48dp tall', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThresholdTheme.light(),
          home: Scaffold(
            body: Center(
              child: TextButton(onPressed: () {}, child: const Text('OK')),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(TextButton)).height,
        greaterThanOrEqualTo(TouchTarget.minimum),
      );
    });
  });

  group('Component themes are defined, so screens stop inheriting stock defaults', () {
    test('every component the audit listed is themed in both schemes', () {
      _themes().forEach((name, theme) {
        expect(theme.filledButtonTheme.style, isNotNull, reason: '$name FilledButton');
        expect(theme.outlinedButtonTheme.style, isNotNull, reason: '$name OutlinedButton');
        expect(theme.textButtonTheme.style, isNotNull, reason: '$name TextButton');
        expect(theme.cardTheme.shape, isNotNull, reason: '$name Card');
        expect(theme.appBarTheme.titleTextStyle, isNotNull, reason: '$name AppBar');
        expect(theme.snackBarTheme.contentTextStyle, isNotNull, reason: '$name SnackBar');
        expect(theme.switchTheme.thumbColor, isNotNull, reason: '$name Switch');
        expect(theme.sliderTheme.activeTrackColor, isNotNull, reason: '$name Slider');
        expect(theme.dialogTheme.shape, isNotNull, reason: '$name Dialog');
        expect(theme.listTileTheme.titleTextStyle, isNotNull, reason: '$name ListTile');
      });
    });

    test('component colors come from the scheme, not from literals', () {
      _themes().forEach((name, theme) {
        expect(theme.appBarTheme.backgroundColor, theme.colorScheme.surface, reason: name);
        expect(theme.appBarTheme.foregroundColor, theme.colorScheme.onSurface, reason: name);
        expect(theme.cardTheme.color, theme.colorScheme.surfaceContainerLow, reason: name);
        expect(theme.snackBarTheme.backgroundColor, theme.colorScheme.inverseSurface, reason: name);
        expect(theme.sliderTheme.activeTrackColor, theme.colorScheme.primary, reason: name);
      });
    });

    test('component radii and elevations come from the token scales', () {
      _themes().forEach((name, theme) {
        expect(Elevations.scale, contains(theme.cardTheme.elevation), reason: '$name Card');
        expect(Elevations.scale, contains(theme.appBarTheme.elevation), reason: '$name AppBar');
        expect(Elevations.scale, contains(theme.dialogTheme.elevation), reason: '$name Dialog');
        expect(Elevations.scale, contains(theme.snackBarTheme.elevation), reason: '$name SnackBar');

        final cardShape = theme.cardTheme.shape! as RoundedRectangleBorder;
        expect(
          Radii.scale,
          contains((cardShape.borderRadius as BorderRadius).topLeft.x),
          reason: '$name Card radius is off scale',
        );
      });
    });

    test('component text styles come from the type scale', () {
      _themes().forEach((name, theme) {
        expect(
          theme.appBarTheme.titleTextStyle!.fontSize,
          ThresholdTypography.base.titleLarge!.fontSize,
          reason: name,
        );
        expect(
          theme.dialogTheme.titleTextStyle!.fontSize,
          ThresholdTypography.base.headlineSmall!.fontSize,
          reason: name,
        );
        expect(
          theme.listTileTheme.titleTextStyle!.fontSize,
          ThresholdTypography.base.titleSmall!.fontSize,
          reason: name,
        );
      });
    });

    test('the slider track is thick enough to drag one-handed', () {
      _themes().forEach((name, theme) {
        expect(theme.sliderTheme.trackHeight, greaterThanOrEqualTo(4), reason: name);
      });
    });

    test('the outlined button border is visible, not a hairline', () {
      _themes().forEach((name, theme) {
        final side = theme.outlinedButtonTheme.style!.side?.resolve(<WidgetState>{});
        expect(side, isNotNull, reason: '$name has no outlined button border');
        expect(side!.width, greaterThan(1.0), reason: '$name border is a hairline');
      });
    });
  });

  group('Both themes render a real screen', () {
    for (final entry in <String, ThemeData>{
      'light': ThresholdTheme.light(),
      'dark': ThresholdTheme.dark(),
    }.entries) {
      testWidgets('${entry.key}: a scaffold with themed components builds clean', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: entry.value,
            home: Scaffold(
              appBar: AppBar(title: const Text('Threshold')),
              body: ListView(
                children: <Widget>[
                  const Card(child: ListTile(title: Text('A row'), subtitle: Text('Detail'))),
                  FilledButton(onPressed: () {}, child: const Text('Answer the door')),
                  OutlinedButton(onPressed: () {}, child: const Text('Settings')),
                  TextButton(onPressed: () {}, child: const Text('Not now')),
                  Switch(value: true, onChanged: (bool _) {}),
                  Slider(value: 0.5, onChanged: (double _) {}),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Answer the door'), findsOneWidget);
      });
    }
  });
}
