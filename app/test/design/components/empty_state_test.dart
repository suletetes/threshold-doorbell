// Empty states (UI/UX audit section 4, "Feedback states": the caption empty state
// was one unstyled line and nothing else in the app had an empty treatment).
//
// The foreground override is the load-bearing part: on the caption surface the
// enforced >=4.5:1 caption foreground decides what is legible, not the theme
// (FR-10.2, NFR-2).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/design/components/components.dart';
import 'package:threshold/design/theme.dart';

Widget _host(Widget child) => MaterialApp(
      theme: ThresholdTheme.light(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('EmptyState rendering', () {
    testWidgets('renders the icon, the title, and the supporting line',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const EmptyState(
            icon: Icons.closed_caption_off_outlined,
            title: 'No captions yet',
            supportingText: 'Captions appear here as your visitor speaks.',
          ),
        ),
      );
      expect(find.byIcon(Icons.closed_caption_off_outlined), findsOneWidget);
      expect(find.text('No captions yet'), findsOneWidget);
      expect(find.text('Captions appear here as your visitor speaks.'),
          findsOneWidget);
    });

    testWidgets('renders an optional action', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          EmptyState(
            icon: Icons.inbox_outlined,
            title: 'Nothing here',
            action: FilledButton(
              key: const ValueKey('empty-action'),
              onPressed: () => taps++,
              child: const Text('Refresh'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('empty-action')));
      expect(taps, 1);
    });

    testWidgets('titleKey lands on the title Text', (tester) async {
      await tester.pumpWidget(
        _host(
          const EmptyState(
            icon: Icons.inbox_outlined,
            title: 'Nothing here',
            titleKey: ValueKey('the-title'),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('the-title')), findsOneWidget);
    });
  });

  group('EmptyState foreground override (FR-10.2, NFR-2)', () {
    testWidgets('an explicit foreground drives the title color',
        (tester) async {
      const enforced = Color(0xFFFFFFFF);
      await tester.pumpWidget(
        _host(
          const EmptyState(
            icon: Icons.closed_caption_off_outlined,
            title: 'No captions yet',
            supportingText: 'Soon',
            foreground: enforced,
          ),
        ),
      );
      expect(tester.widget<Text>(find.text('No captions yet')).style?.color,
          enforced);
      // The supporting line is derived from the same enforced color, never from
      // the theme, so it cannot drift off the caption background.
      final supporting = tester.widget<Text>(find.text('Soon')).style!.color!;
      expect(supporting.r, enforced.r);
      expect(supporting.g, enforced.g);
      expect(supporting.b, enforced.b);
    });

    testWidgets('without an override it falls back to the theme',
        (tester) async {
      await tester.pumpWidget(
        _host(const EmptyState(
            icon: Icons.inbox_outlined, title: 'Nothing here')),
      );
      final context = tester.element(find.byType(EmptyState));
      expect(
        tester.widget<Text>(find.text('Nothing here')).style?.color,
        Theme.of(context).colorScheme.onSurface,
      );
    });
  });

  group('EmptyState semantics (G4)', () {
    testWidgets('title and supporting line are announced as one node',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const EmptyState(
            icon: Icons.closed_caption_off_outlined,
            title: 'No captions yet',
            supportingText: 'Captions appear here as your visitor speaks.',
          ),
        ),
      );
      expect(
        find.bySemanticsLabel(
          'No captions yet Captions appear here as your visitor speaks.',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('an explicit semanticsLabel wins', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const EmptyState(
            icon: Icons.closed_caption_off_outlined,
            title: 'No captions yet',
            semanticsLabel: 'Waiting for your visitor to speak',
          ),
        ),
      );
      expect(find.bySemanticsLabel('Waiting for your visitor to speak'),
          findsOneWidget);
      handle.dispose();
    });
  });
}
