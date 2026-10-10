// The shared badge (UI/UX audit section 4, "Component consistency": the mode
// badge was a bespoke pill built from a raw 0xCC1565C0 and a raw radius).
// The load-bearing property here is opacity: this pill is drawn over inbound
// doorbell video, where a translucent fill has no contrast guarantee at all.

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
  group('Pill rendering', () {
    testWidgets('renders the label and the optional icon', (tester) async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => Pill(
              label: 'Clarity Mode',
              color: ThresholdSemanticColors.of(context).live,
              icon: Icons.cloud_outlined,
            ),
          ),
        ),
      );
      expect(find.text('Clarity Mode'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
    });

    testWidgets('renders without an icon', (tester) async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => Pill(
              label: 'Privacy Mode',
              color: ThresholdSemanticColors.of(context).live,
            ),
          ),
        ),
      );
      expect(find.text('Privacy Mode'), findsOneWidget);
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('is fully rounded and uses the label type role',
        (tester) async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => Pill(
              label: 'Live',
              color: ThresholdSemanticColors.of(context).live,
            ),
          ),
        ),
      );
      final decoration = tester
          .widget<DecoratedBox>(find.descendant(
            of: find.byType(Pill),
            matching: find.byType(DecoratedBox),
          ))
          .decoration as BoxDecoration;
      expect(decoration.borderRadius, Radii.roundedFull);

      final context = tester.element(find.byType(Pill));
      final expected = Theme.of(context).textTheme.labelMedium!;
      expect(tester.widget<Text>(find.text('Live')).style?.fontSize,
          expected.fontSize);
    });
  });

  group('Pill contrast over video', () {
    testWidgets('the fill is opaque in both schemes', (tester) async {
      for (final dark in <bool>[false, true]) {
        await tester.pumpWidget(
          _host(
            Builder(
              builder: (context) => Pill(
                label: 'Live',
                color: ThresholdSemanticColors.of(context).live,
              ),
            ),
            dark: dark,
          ),
        );
        final decoration = tester
            .widget<DecoratedBox>(find.descendant(
              of: find.byType(Pill),
              matching: find.byType(DecoratedBox),
            ))
            .decoration as BoxDecoration;
        expect(
          decoration.color!.a,
          1.0,
          reason: 'a translucent pill over video has no contrast guarantee',
        );
      }
    });

    testWidgets('the label clears 4.5:1 against the pill fill for every role',
        (tester) async {
      for (final dark in <bool>[false, true]) {
        await tester.pumpWidget(_host(const SizedBox.shrink(), dark: dark));
        final context = tester.element(find.byType(Scaffold));
        final semantic = ThresholdSemanticColors.of(context);
        for (final role in <Color>[
          semantic.live,
          semantic.recording,
          semantic.success,
          semantic.warning,
          semantic.danger,
        ]) {
          // Asserted against the fill the widget actually paints. This caught a
          // real 4.47:1 failure on the light-scheme recording role when the tint
          // was heavier.
          expect(
            meetsContrastFloor(role, Pill.fillFor(context, role)),
            isTrue,
            reason: 'pill label must clear 4.5:1 in ${dark ? 'dark' : 'light'}',
          );
        }
      }
    });
  });

  group('Pill semantics (G4)', () {
    testWidgets('announces the label by default', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => Pill(
              label: 'Clarity Mode',
              color: ThresholdSemanticColors.of(context).live,
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Clarity Mode'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a richer semanticsLabel replaces the visible label',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => Pill(
              label: 'Clarity Mode',
              semanticsLabel: 'Active caption mode: Clarity Mode',
              color: ThresholdSemanticColors.of(context).live,
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Active caption mode: Clarity Mode'),
          findsOneWidget);
      expect(find.bySemanticsLabel('Clarity Mode'), findsNothing);
      handle.dispose();
    });
  });
}
