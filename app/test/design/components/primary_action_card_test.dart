// The hero action (UI/UX audit C5: the primary action had no visual weight).
// These tests pin what "unmistakable" means in code: real size, an icon, a
// supporting line, one button in the semantics tree, and a press animation that
// a reduced-motion user never sees.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/design/components/components.dart';
import 'package:threshold/design/theme.dart';
import 'package:threshold/design/tokens.dart';

Widget _host(Widget child, {bool disableAnimations = false}) => MaterialApp(
      theme: ThresholdTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(body: Center(child: child)),
      ),
    );

PrimaryActionCard _card({VoidCallback? onPressed, String? supporting}) =>
    PrimaryActionCard(
      key: const ValueKey('hero'),
      icon: Icons.doorbell_outlined,
      label: 'Answer the door',
      supportingText: supporting,
      onPressed: onPressed ?? () {},
    );

void main() {
  group('PrimaryActionCard weight (audit C5)', () {
    testWidgets('renders the label, the icon, and the supporting line',
        (tester) async {
      await tester.pumpWidget(
          _host(_card(supporting: 'Captions appear as your visitor speaks.')));
      expect(find.text('Answer the door'), findsOneWidget);
      expect(
          find.text('Captions appear as your visitor speaks.'), findsOneWidget);
      expect(find.byIcon(Icons.doorbell_outlined), findsOneWidget);
    });

    testWidgets('is at least two touch targets tall', (tester) async {
      await tester.pumpWidget(_host(_card()));
      final size = tester.getSize(find.byKey(const ValueKey('hero')));
      expect(
          size.height, greaterThanOrEqualTo(PrimaryActionCard.minimumHeight));
      expect(PrimaryActionCard.minimumHeight,
          greaterThanOrEqualTo(TouchTarget.minimum * 2));
    });

    testWidgets('uses the headline role for the label, not a raw font size',
        (tester) async {
      await tester.pumpWidget(_host(_card()));
      final context = tester.element(find.byType(PrimaryActionCard));
      final expected = Theme.of(context).textTheme.headlineSmall!;
      final label = tester.widget<Text>(find.text('Answer the door'));
      expect(label.style?.fontSize, expected.fontSize);
      expect(label.style?.fontWeight, expected.fontWeight);
    });

    testWidgets('omitting the supporting line renders only the label',
        (tester) async {
      await tester.pumpWidget(_host(_card()));
      expect(find.text('Answer the door'), findsOneWidget);
      expect(find.byType(Text), findsOneWidget);
    });
  });

  group('PrimaryActionCard interaction', () {
    testWidgets('tapping fires onPressed', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(_card(onPressed: () => taps++)));
      await tester.tap(find.byKey(const ValueKey('hero')));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('press scales the card down, release restores it',
        (tester) async {
      await tester.pumpWidget(_host(_card()));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('hero'))),
      );
      await tester.pump(Motion.fast);
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        PrimaryActionCard.pressedScale,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
          tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.0);
    });
  });

  group('PrimaryActionCard motion respects reduced motion (audit principle 3)',
      () {
    testWidgets('the press duration collapses to zero when animations are off',
        (tester) async {
      await tester.pumpWidget(_host(_card(), disableAnimations: true));
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
        Motion.instant,
      );
    });

    testWidgets('the press duration is a motion token otherwise',
        (tester) async {
      await tester.pumpWidget(_host(_card()));
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
        Motion.fast,
      );
    });
  });

  group('PrimaryActionCard semantics (G4)', () {
    testWidgets('announces exactly one button using the label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(_card(supporting: 'Supporting line')));
      expect(find.bySemanticsLabel('Answer the door'), findsOneWidget);
      // The inner fragments are excluded so the reader hears one control.
      expect(find.bySemanticsLabel('Supporting line'), findsNothing);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Answer the door')),
        containsSemantics(label: 'Answer the door', isButton: true),
      );
      handle.dispose();
    });

    testWidgets('an explicit semanticsLabel wins', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          PrimaryActionCard(
            icon: Icons.doorbell_outlined,
            label: 'Answer the door',
            semanticsLabel: 'Answer the door and show captions',
            onPressed: () {},
          ),
        ),
      );
      expect(find.bySemanticsLabel('Answer the door and show captions'),
          findsOneWidget);
      handle.dispose();
    });
  });
}
