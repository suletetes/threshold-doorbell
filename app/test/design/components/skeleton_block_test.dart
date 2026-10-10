// Loading placeholders (UI/UX audit section 4, "Perceived performance": there
// were no skeletons anywhere, so the first frame of any data-bearing surface was
// empty).
//
// Two behaviors are pinned here because both are deliberate departures from the
// usual shimmer: the pulse is finite so the tree stays settleable, and reduced
// motion collapses it to the resting value with no movement at all.

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

BoxDecoration _decoration(WidgetTester tester) => tester
    .widget<DecoratedBox>(
      find.descendant(
          of: find.byType(SkeletonBlock), matching: find.byType(DecoratedBox)),
    )
    .decoration as BoxDecoration;

void main() {
  group('SkeletonBlock geometry', () {
    testWidgets('honors the requested height and width', (tester) async {
      await tester.pumpWidget(
        _host(const SkeletonBlock(
            height: Spacing.space6, width: Spacing.space10)),
      );
      final size = tester.getSize(find.byType(SkeletonBlock));
      expect(size.height, Spacing.space6);
      expect(size.width, Spacing.space10);
    });

    testWidgets('fills the available width when no width is given',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
              width: 300, child: SkeletonBlock(height: Spacing.space5)),
        ),
      );
      expect(tester.getSize(find.byType(SkeletonBlock)).width, 300);
    });

    testWidgets('uses a radius token', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: SkeletonBlock(height: Spacing.space5)));
      await tester.pump();
      final decoration = tester
          .widget<DecoratedBox>(
            find.descendant(
              of: find.byType(SkeletonBlock),
              matching: find.byType(DecoratedBox),
            ),
          )
          .decoration as BoxDecoration;
      expect(Radii.scale, contains(Radii.small));
      expect(decoration.borderRadius, Radii.roundedSmall);
    });
  });

  group('SkeletonBlock pulse', () {
    testWidgets('pulses between the rest and peak opacities', (tester) async {
      await tester
          .pumpWidget(_host(const SkeletonBlock(height: Spacing.space6)));
      expect(_decoration(tester).color!.a,
          closeTo(SkeletonBlock.restOpacity, 1e-6));
      // Half a cycle in, the fill has risen toward the peak.
      await tester.pump(Motion.slow ~/ 2);
      final mid = _decoration(tester).color!.a;
      expect(mid, greaterThan(SkeletonBlock.restOpacity));
      expect(mid, lessThanOrEqualTo(SkeletonBlock.peakOpacity + 1e-6));
    });

    testWidgets('the pulse is finite, so the tree settles', (tester) async {
      await tester
          .pumpWidget(_host(const SkeletonBlock(height: Spacing.space6)));
      // An infinite shimmer would hang here forever.
      await tester.pumpAndSettle();
      expect(_decoration(tester).color!.a,
          closeTo(SkeletonBlock.restOpacity, 1e-6));
    });

    testWidgets('it rests at the resting opacity, not invisible',
        (tester) async {
      await tester
          .pumpWidget(_host(const SkeletonBlock(height: Spacing.space6)));
      await tester.pumpAndSettle();
      expect(_decoration(tester).color!.a, greaterThan(0));
    });
  });

  group('SkeletonBlock respects reduced motion (audit principle 3)', () {
    testWidgets('lands on the resting value in the first frame and never moves',
        (tester) async {
      await tester.pumpWidget(
        _host(const SkeletonBlock(height: Spacing.space6),
            disableAnimations: true),
      );
      final first = _decoration(tester).color!.a;
      expect(first, closeTo(SkeletonBlock.restOpacity, 1e-6));
      await tester.pump(Motion.slow);
      expect(_decoration(tester).color!.a, closeTo(first, 1e-6));
    });
  });

  group('SkeletonBlock semantics (G4)', () {
    testWidgets('is hidden from the semantics tree by default', (tester) async {
      final handle = tester.ensureSemantics();
      await tester
          .pumpWidget(_host(const SkeletonBlock(height: Spacing.space6)));
      // A drawing of content that does not exist yet must not be announced.
      expect(
        find.descendant(
          of: find.byType(SkeletonBlock),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('an explicit label is announced once', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const SkeletonBlock(
              height: Spacing.space6, semanticsLabel: 'Loading captions'),
        ),
      );
      expect(find.bySemanticsLabel('Loading captions'), findsOneWidget);
      handle.dispose();
    });
  });
}
