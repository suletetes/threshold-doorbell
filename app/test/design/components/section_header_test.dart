// Section headers (UI/UX audit section 4, "Information architecture": settings
// was a flat list with no grouping hierarchy, and its inline helper used a raw
// fontSize of 18 with a raw w700).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/design/components/components.dart';
import 'package:threshold/design/theme.dart';

Widget _host(Widget child) => MaterialApp(
      theme: ThresholdTheme.light(),
      home: Scaffold(body: Column(children: <Widget>[child])),
    );

void main() {
  group('SectionHeader rendering', () {
    testWidgets('renders the title from the type scale, not a raw size',
        (tester) async {
      await tester
          .pumpWidget(_host(const SectionHeader(title: 'Privacy and data')));
      expect(find.text('Privacy and data'), findsOneWidget);
      final context = tester.element(find.byType(SectionHeader));
      final expected = Theme.of(context).textTheme.titleSmall!;
      final rendered = tester.widget<Text>(find.text('Privacy and data'));
      expect(rendered.style?.fontSize, expected.fontSize);
      expect(rendered.style?.fontWeight, expected.fontWeight);
    });

    testWidgets('renders the optional supporting line', (tester) async {
      await tester.pumpWidget(
        _host(
          const SectionHeader(
            title: 'Alerts',
            supportingText: 'How your phone tells you someone is there.',
          ),
        ),
      );
      expect(find.text('How your phone tells you someone is there.'),
          findsOneWidget);
    });

    testWidgets('the title is sentence case, never transformed to caps',
        (tester) async {
      await tester
          .pumpWidget(_host(const SectionHeader(title: 'Privacy and data')));
      // All caps defeats word-shape recognition; this product cannot afford it.
      expect(find.text('PRIVACY AND DATA'), findsNothing);
      expect(find.text('Privacy and data'), findsOneWidget);
    });
  });

  group('SectionHeader density', () {
    testWidgets('a dense header drops the accent rule and steps down the scale',
        (tester) async {
      await tester.pumpWidget(
          _host(const SectionHeader(title: 'Haptic reference', dense: true)));
      final context = tester.element(find.byType(SectionHeader));
      final theme = Theme.of(context).textTheme;
      final rendered = tester.widget<Text>(find.text('Haptic reference'));
      expect(rendered.style?.fontSize, theme.labelMedium!.fontSize);
      expect(rendered.style?.fontSize, lessThan(theme.titleSmall!.fontSize!));
      expect(rendered.style?.color,
          Theme.of(context).colorScheme.onSurfaceVariant);
      // The accent rule is the only DecoratedBox a header draws.
      expect(
        find.descendant(
            of: find.byType(SectionHeader),
            matching: find.byType(DecoratedBox)),
        findsNothing,
      );
    });

    testWidgets('a normal header draws the accent rule', (tester) async {
      await tester.pumpWidget(_host(const SectionHeader(title: 'Captions')));
      expect(
        find.descendant(
            of: find.byType(SectionHeader),
            matching: find.byType(DecoratedBox)),
        findsOneWidget,
      );
    });

    testWidgets('a dense header sits tighter than a normal one',
        (tester) async {
      await tester.pumpWidget(_host(const SectionHeader(title: 'Alerts')));
      final normal = tester.getSize(find.byType(SectionHeader)).height;
      await tester
          .pumpWidget(_host(const SectionHeader(title: 'Alerts', dense: true)));
      final dense = tester.getSize(find.byType(SectionHeader)).height;
      expect(dense, lessThan(normal));
    });
  });

  group('SectionHeader semantics (G4)', () {
    testWidgets('announces itself as a header with the title', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(const SectionHeader(title: 'Captions')));
      expect(
        tester.getSemantics(find.bySemanticsLabel('Captions')),
        containsSemantics(label: 'Captions', isHeader: true),
      );
      handle.dispose();
    });

    testWidgets('the supporting line does not add a second node',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
            const SectionHeader(title: 'Alerts', supportingText: 'Supporting')),
      );
      expect(find.bySemanticsLabel('Alerts'), findsOneWidget);
      expect(find.bySemanticsLabel('Supporting'), findsNothing);
      handle.dispose();
    });
  });
}
