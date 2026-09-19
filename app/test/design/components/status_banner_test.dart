// The shared status banner (UI/UX audit section 3.6). Four surfaces previously
// hand-rolled the same idea; these tests pin the one component that replaced
// them: the variant carries the meaning, the message keeps full surface
// contrast, the action reaches real button weight and the 48dp floor, and the
// message announces itself.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/design/colors.dart';
import 'package:threshold/design/components/components.dart';
import 'package:threshold/design/theme.dart';
import 'package:threshold/design/tokens.dart';
import 'package:threshold/settings/contrast.dart';

Widget _host(Widget child, {bool dark = false}) => MaterialApp(
      theme: dark ? ThresholdTheme.dark() : ThresholdTheme.light(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('StatusBanner variants (audit section 3.6)', () {
    testWidgets('renders the message and the variant icon', (tester) async {
      await tester.pumpWidget(
        _host(
          const StatusBanner(
            message: 'Replies are unavailable on this device.',
            variant: StatusVariant.warning,
          ),
        ),
      );
      expect(find.text('Replies are unavailable on this device.'), findsOneWidget);
      expect(find.byIcon(StatusBanner.iconFor(StatusVariant.warning)), findsOneWidget);
    });

    testWidgets('every variant has a distinct default icon', (tester) async {
      final icons = StatusVariant.values.map(StatusBanner.iconFor).toSet();
      expect(icons.length, StatusVariant.values.length);
    });

    testWidgets('an explicit icon overrides the variant default', (tester) async {
      await tester.pumpWidget(
        _host(
          const StatusBanner(message: 'Offline', icon: Icons.wifi_off),
        ),
      );
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      expect(find.byIcon(StatusBanner.iconFor(StatusVariant.info)), findsNothing);
    });

    testWidgets('each variant maps to its semantic role in both schemes', (tester) async {
      for (final dark in <bool>[false, true]) {
        await tester.pumpWidget(
          _host(const StatusBanner(message: 'x'), dark: dark),
        );
        final context = tester.element(find.byType(StatusBanner));
        final semantic = ThresholdSemanticColors.of(context);
        expect(StatusBanner.colorFor(context, StatusVariant.warning), semantic.warning);
        expect(StatusBanner.colorFor(context, StatusVariant.danger), semantic.danger);
        expect(StatusBanner.colorFor(context, StatusVariant.success), semantic.success);
        expect(
          StatusBanner.colorFor(context, StatusVariant.info),
          Theme.of(context).colorScheme.primary,
        );
      }
    });
  });

  group('StatusBanner legibility', () {
    testWidgets('the message keeps at least 4.5:1 on every variant, both schemes',
        (tester) async {
      for (final dark in <bool>[false, true]) {
        for (final variant in StatusVariant.values) {
          await tester.pumpWidget(
            _host(StatusBanner(message: 'x', variant: variant), dark: dark),
          );
          final context = tester.element(find.byType(StatusBanner));
          final scheme = Theme.of(context).colorScheme;
          // Asserted against the composite the widget actually paints, not a
          // second copy of the formula.
          expect(
            meetsContrastFloor(
              scheme.onSurface,
              StatusBanner.backgroundFor(context, variant),
            ),
            isTrue,
            reason: 'variant $variant in ${dark ? 'dark' : 'light'} must clear 4.5:1',
          );
        }
      }
    });

    testWidgets('the banner fill is opaque so it is legible over video', (tester) async {
      await tester.pumpWidget(_host(const StatusBanner(message: 'x')));
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(StatusBanner), matching: find.byType(DecoratedBox)).first,
      );
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color!.a, 1.0);
    });
  });

  group('StatusBanner action (audit section 5: icon and proper button weight)', () {
    testWidgets('renders a filled button with an icon and fires onPressed', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          StatusBanner(
            message: 'Replies unavailable.',
            variant: StatusVariant.warning,
            action: StatusBannerAction(
              label: 'Open Ring app',
              icon: Icons.open_in_new,
              buttonKey: const ValueKey('banner-action'),
              onPressed: () => taps++,
            ),
          ),
        ),
      );
      // FilledButton.icon builds a private subclass, so match on the supertype.
      expect(find.byWidgetPredicate((w) => w is FilledButton), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('banner-action')));
      expect(taps, 1);
    });

    testWidgets('the action meets the 48dp minimum target (audit section 4)', (tester) async {
      await tester.pumpWidget(
        _host(
          StatusBanner(
            message: 'x',
            action: StatusBannerAction(
              label: 'OK',
              buttonKey: const ValueKey('banner-action'),
              onPressed: () {},
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byKey(const ValueKey('banner-action')));
      expect(size.height, greaterThanOrEqualTo(TouchTarget.minimum));
    });

    testWidgets('no action means no button', (tester) async {
      await tester.pumpWidget(_host(const StatusBanner(message: 'x')));
      expect(find.byWidgetPredicate((w) => w is ButtonStyleButton), findsNothing);
    });
  });

  group('StatusBanner semantics (G4)', () {
    testWidgets('the message is a live region announced once', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(const StatusBanner(message: 'Captions are unavailable right now.')),
      );
      expect(
        find.bySemanticsLabel('Captions are unavailable right now.'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('liveRegion can be turned off for static copy', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(const StatusBanner(message: 'Static note', liveRegion: false)),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Static note')),
        containsSemantics(label: 'Static note', isLiveRegion: false),
      );
      handle.dispose();
    });

    testWidgets('an explicit semanticsLabel overrides the visible message', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const StatusBanner(
            message: 'Privacy Mode unavailable',
            semanticsLabel: 'Privacy Mode is unavailable until the model finishes downloading.',
          ),
        ),
      );
      expect(
        find.bySemanticsLabel(
          'Privacy Mode is unavailable until the model finishes downloading.',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the action carries its own button semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          StatusBanner(
            message: 'x',
            action: StatusBannerAction(label: 'Try again', onPressed: () {}),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Try again'), findsOneWidget);
      handle.dispose();
    });
  });

  group('StatusBanner call-site keys', () {
    testWidgets('messageKey lands on the message Text', (tester) async {
      await tester.pumpWidget(
        _host(
          const StatusBanner(message: 'x', messageKey: ValueKey('the-message')),
        ),
      );
      expect(find.byKey(const ValueKey('the-message')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('the-message'))).data, 'x');
    });
  });
}
