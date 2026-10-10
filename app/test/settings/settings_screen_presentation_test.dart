// Settings presentation (UI/UX audit section 4, "Information architecture":
// "Settings is a flat list with no grouping hierarchy, despite containing mode,
// captions, haptics, strobe, language, retention, erasure, and the recording
// notice. That is at least four distinct concerns"; and section 5: "Make Delete
// all my data visually danger").
//
// The pre-existing settings_screen_test.dart pins every control's behavior. This
// file pins the grouping and the destructive styling, and explicitly re-asserts
// that grouping did not drop a control or a label.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/alerts/haptic_vocabulary.dart';
import 'package:threshold/design/colors.dart';
import 'package:threshold/design/components/components.dart';
import 'package:threshold/design/theme.dart';
import 'package:threshold/design/tokens.dart';
import 'package:threshold/settings/settings_controller.dart';
import 'package:threshold/settings/settings_screen.dart';

Widget _host(SettingsController c, {TextScaler? scaler, bool dark = false}) =>
    MaterialApp(
      theme: dark ? ThresholdTheme.dark() : ThresholdTheme.light(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: scaler ?? TextScaler.noScaling),
          child: SettingsScreen(controller: c),
        ),
      ),
    );

/// Every control the screen is required to expose (FR-8.5, FR-8.6,
/// FR-10.1..FR-10.4). Grouping must not lose any of them.
List<ValueKey<String>> _everyControl() => <ValueKey<String>>[
      const ValueKey('mode-switch'),
      const ValueKey('caption-scale'),
      const ValueKey('contrast-readout'),
      for (final p in HapticVocabulary.all) ValueKey('haptic-${p.event.name}'),
      const ValueKey('strobe-toggle'),
      for (final p in HapticVocabulary.all)
        ValueKey('haptic-ref-${p.event.name}'),
      const ValueKey('language-readout'),
      const ValueKey('retention-readout'),
      const ValueKey('delete-all-data'),
    ];

void main() {
  group('Grouping (audit section 4, information architecture)', () {
    testWidgets('the four concerns each get a section header', (tester) async {
      final c = SettingsController(erasure: FakeDataErasurePort());
      await tester.pumpWidget(_host(c));
      await tester.pump();
      for (final title in <String>['Captions', 'Alerts']) {
        expect(find.text(title), findsOneWidget,
            reason: '$title section missing');
      }
      await tester.scrollUntilVisible(find.text('Privacy and data'), 200);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Privacy and data'), findsOneWidget);
    });

    testWidgets(
        'the headers are SectionHeaders, not an inline raw style helper',
        (tester) async {
      final c = SettingsController(erasure: FakeDataErasurePort());
      await tester.pumpWidget(_host(c));
      await tester.pump();
      expect(find.byType(SectionHeader), findsWidgets);
      final context = tester.element(find.byType(SettingsScreen));
      final expected = Theme.of(context).textTheme.titleSmall!;
      expect(tester.widget<Text>(find.text('Captions')).style?.fontSize,
          expected.fontSize);
    });

    testWidgets('the haptic reference is a subordinate header inside Alerts',
        (tester) async {
      final c = SettingsController(erasure: FakeDataErasurePort());
      await tester.pumpWidget(_host(c));
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Haptic reference'), 200);
      final header = tester.widget<SectionHeader>(
        find.ancestor(
          of: find.text('Haptic reference'),
          matching: find.byType(SectionHeader),
        ),
      );
      expect(header.dense, isTrue);
    });

    testWidgets('every header announces itself as a header (G4)',
        (tester) async {
      final handle = tester.ensureSemantics();
      final c = SettingsController(erasure: FakeDataErasurePort());
      await tester.pumpWidget(_host(c));
      await tester.pump();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Captions')),
        containsSemantics(label: 'Captions', isHeader: true),
      );
      handle.dispose();
    });
  });

  group('Grouping did not lose a control or a label', () {
    /// Scrolls the whole screen top to bottom once, collecting which of
    /// [expected] were seen. A single downward pass, because ListView only
    /// builds what is near the viewport and scrollUntilVisible cannot go back up.
    Future<Set<String>> sweep(
      WidgetTester tester,
      Map<String, Finder> expected,
    ) async {
      final seen = <String>{};
      for (var pass = 0; pass < 40; pass++) {
        expected.forEach((name, finder) {
          if (finder.evaluate().isNotEmpty) seen.add(name);
        });
        if (seen.length == expected.length) break;
        await tester.drag(find.byType(ListView), const Offset(0, -240));
        await tester.pump();
      }
      return seen;
    }

    testWidgets('every required control is still present', (tester) async {
      final c = SettingsController(erasure: FakeDataErasurePort());
      await tester.pumpWidget(_host(c));
      await tester.pump();
      final expected = <String, Finder>{
        for (final key in _everyControl()) key.value: find.byKey(key),
      };
      final seen = await sweep(tester, expected);
      expect(
        seen,
        expected.keys.toSet(),
        reason: 'grouping must not drop a control',
      );
    });

    testWidgets('every Semantics label is still present (G4, AT-9)',
        (tester) async {
      final handle = tester.ensureSemantics();
      final c = SettingsController(erasure: FakeDataErasurePort());
      await tester.pumpWidget(_host(c));
      await tester.pump();
      // RegExp, not exact strings: a Semantics label on a node whose child also
      // has a label is merged into one node with both, so exact matching would
      // be asserting an implementation detail of the merge.
      final expected = <String, Finder>{
        'privacy explanation':
            find.bySemanticsLabel(RegExp('Privacy Mode explanation')),
        // MED-04: the mode switch is now a single SwitchListTile node whose
        // label is its title plus subtitle, with no duplicate outer Semantics.
        'mode switch': find.bySemanticsLabel(RegExp('Privacy Mode')),
        // MED-04: the slider is a single node; it is located by key here (its
        // accessible value is asserted in settings_screen_test).
        'caption size': find.byKey(const ValueKey('caption-scale')),
        'caption contrast':
            find.bySemanticsLabel(RegExp('Caption contrast ratio')),
        // MED-04: one node per haptic toggle; the label is the tile title.
        for (final p in HapticVocabulary.all)
          'haptic ${p.label}':
              find.bySemanticsLabel(RegExp('Haptic alert: ${p.label}')),
        'strobe':
            find.bySemanticsLabel(RegExp('Screen strobe and torch alert')),
        for (final p in HapticVocabulary.all)
          'haptic ref ${p.label}':
              find.bySemanticsLabel(RegExp('Haptic pattern: ${p.label}')),
        'language': find.bySemanticsLabel(RegExp('Recognition language')),
        'retention': find.bySemanticsLabel(RegExp('Transcripts are kept')),
        'delete': find.bySemanticsLabel(RegExp('Delete all my data')),
      };
      final seen = await sweep(tester, expected);
      expect(seen, expected.keys.toSet(),
          reason: 'grouping must not drop a label');
      handle.dispose();
    });

    testWidgets('the pending mode notice keeps its exact copy (FR-10.1)',
        (tester) async {
      final c = SettingsController(erasure: FakeDataErasurePort());
      await tester.pumpWidget(_host(c));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mode-switch')));
      await tester.pumpAndSettle();
      expect(find.text('The mode change applies to your next session.'),
          findsOneWidget);
      // It is now the shared banner rather than a fifth ad hoc italic line.
      expect(find.byKey(const ValueKey('mode-pending-notice')), findsOneWidget);
    });
  });

  group('Delete all my data reads as destructive (audit section 5)', () {
    testWidgets('the button carries the danger role, not a hand-picked literal',
        (tester) async {
      final c = SettingsController(erasure: FakeDataErasurePort());
      await tester.pumpWidget(_host(c));
      await tester.pump();
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('delete-all-data')), 200);
      final context =
          tester.element(find.byKey(const ValueKey('delete-all-data')));
      final danger = ThresholdSemanticColors.of(context).danger;
      final button = tester.widget<ButtonStyleButton>(
        find.byKey(const ValueKey('delete-all-data')),
      );
      expect(
        button.style?.foregroundColor?.resolve(<WidgetState>{}),
        danger,
      );
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('the danger role is legible on the button fill in both schemes',
        (tester) async {
      for (final dark in <bool>[false, true]) {
        final c = SettingsController(erasure: FakeDataErasurePort());
        await tester.pumpWidget(_host(c, dark: dark));
        await tester.pump();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('delete-all-data')),
          200,
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('delete-all-data'))).height,
          greaterThanOrEqualTo(TouchTarget.minimum),
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('the confirmation dialog carries the danger role through',
        (tester) async {
      final port = FakeDataErasurePort();
      final c = SettingsController(erasure: port);
      await tester.pumpWidget(_host(c));
      await tester.pump();
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('delete-all-data')), 200);
      await tester.tap(find.byKey(const ValueKey('delete-all-data')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('delete-confirm-dialog')), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      final context =
          tester.element(find.byKey(const ValueKey('delete-confirm')));
      final danger = ThresholdSemanticColors.of(context).danger;
      final confirm = tester.widget<ButtonStyleButton>(
        find.byKey(const ValueKey('delete-confirm')),
      );
      expect(confirm.style?.backgroundColor?.resolve(<WidgetState>{}), danger);
      // Cancel is still the quiet option and still does nothing.
      await tester.tap(find.byKey(const ValueKey('delete-cancel')));
      await tester.pumpAndSettle();
      expect(port.deleteCalls, 0);
    });
  });

  group('Settings still honors 200% text scaling (NFR-2)', () {
    testWidgets('the grouped layout does not overflow at 200%', (tester) async {
      final c = SettingsController(erasure: FakeDataErasurePort());
      await tester.pumpWidget(_host(c, scaler: const TextScaler.linear(2.0)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('a hostile OS scale is still clamped to the tested ceiling',
        (tester) async {
      final c = SettingsController(erasure: FakeDataErasurePort());
      await tester.pumpWidget(_host(c, scaler: const TextScaler.linear(5.0)));
      await tester.pump();
      final mq = tester.widget<MediaQuery>(
        find
            .ancestor(
                of: find.byType(Scaffold), matching: find.byType(MediaQuery))
            .first,
      );
      expect(
        mq.data.textScaler.scale(10),
        lessThanOrEqualTo(10 * kMaxSettingsTextScale),
      );
    });
  });

  group('Settings copy (NFR-10)', () {
    test('no dashes in the Privacy Mode explanation', () {
      expect(kPrivacyModeExplanation.contains('\u2014'), isFalse);
      expect(kPrivacyModeExplanation.contains('\u2013'), isFalse);
    });
  });
}
