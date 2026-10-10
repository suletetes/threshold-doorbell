import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/captions/language_selection.dart';
import 'package:threshold/settings/settings_controller.dart';
import 'package:threshold/settings/settings_screen.dart';

Widget _wrap(SettingsController c, {TextScaler? scaler}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: scaler ?? TextScaler.noScaling),
        child: SettingsScreen(controller: c),
      ),
    );

void main() {
  group('SettingsScreen (Task 24, FR-8.6, FR-10.1..10.4, NFR-2; AT-9)', () {
    testWidgets('renders all sections and the Privacy-Mode explanation',
        (tester) async {
      final c = SettingsController(erasure: FakeDataErasurePort());
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      expect(find.byKey(const ValueKey('mode-switch')), findsOneWidget);
      expect(find.byKey(const ValueKey('caption-scale')), findsOneWidget);
      expect(find.textContaining('Privacy Mode keeps everything on your phone'),
          findsOneWidget);
      // strobe-toggle and delete-all-data are lower in the scroll view.
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('strobe-toggle')), 200);
      expect(find.byKey(const ValueKey('strobe-toggle')), findsOneWidget);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('delete-all-data')), 200);
      expect(find.byKey(const ValueKey('delete-all-data')), findsOneWidget);
    });

    testWidgets(
        'mode switch queues to next session, shows the notice (FR-10.1)',
        (tester) async {
      final c = SettingsController(erasure: FakeDataErasurePort());
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mode-switch')));
      await tester.pump();
      expect(c.settings.pendingMode, CaptionMode.privacy);
      expect(c.settings.activeMode, CaptionMode.clarity);
      expect(
          find.textContaining('applies to your next session'), findsOneWidget);
    });

    testWidgets('strobe is off by default and toggles on tap (FR-9.4)',
        (tester) async {
      final c = SettingsController(erasure: FakeDataErasurePort());
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      expect(c.settings.strobeEnabled, isFalse);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('strobe-toggle')), 200);
      await tester.tap(find.byKey(const ValueKey('strobe-toggle')));
      await tester.pump();
      expect(c.settings.strobeEnabled, isTrue);
    });

    testWidgets('contrast readout shows a ratio at or above 4.5 (FR-10.2)',
        (tester) async {
      final c = SettingsController(erasure: FakeDataErasurePort());
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      expect(find.byKey(const ValueKey('contrast-readout')), findsOneWidget);
      expect(c.settings.captionContrastRatio >= 4.5, isTrue);
    });

    testWidgets('delete all data requires confirmation then erases (FR-8.6)',
        (tester) async {
      final port = FakeDataErasurePort();
      final c = SettingsController(erasure: port);
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('delete-all-data')), 200);
      await tester.tap(find.byKey(const ValueKey('delete-all-data')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('delete-confirm-dialog')), findsOneWidget);
      // Cancel does nothing.
      await tester.tap(find.byKey(const ValueKey('delete-cancel')));
      await tester.pumpAndSettle();
      expect(port.deleteCalls, 0);
      // Confirm erases and shows a success banner (HIGH-08).
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('delete-all-data')), 200);
      await tester.tap(find.byKey(const ValueKey('delete-all-data')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-confirm')));
      await tester.pumpAndSettle();
      expect(port.deleteCalls, 1);
      expect(c.erasureStatus, ErasureStatus.success);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('delete-success-banner')), 200);
      expect(
          find.byKey(const ValueKey('delete-success-banner')), findsOneWidget);
    });

    testWidgets(
        'a failed erasure shows a failure banner with a retry (HIGH-08)',
        (tester) async {
      final port = FakeDataErasurePort(succeeds: false);
      final c = SettingsController(erasure: port);
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('delete-all-data')), 200);
      await tester.tap(find.byKey(const ValueKey('delete-all-data')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-confirm')));
      await tester.pumpAndSettle();
      expect(c.erasureStatus, ErasureStatus.failure);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('delete-failure-banner')), 200);
      expect(
          find.byKey(const ValueKey('delete-failure-banner')), findsOneWidget);
      // Retry re-attempts the erasure (the resident already confirmed).
      await tester.ensureVisible(find.byKey(const ValueKey('delete-retry')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-retry')));
      await tester.pumpAndSettle();
      expect(port.deleteCalls, 2);
    });

    testWidgets('honors OS text scaling to 200% without overflow (NFR-2)',
        (tester) async {
      final c = SettingsController(erasure: FakeDataErasurePort());
      await tester.pumpWidget(_wrap(c, scaler: const TextScaler.linear(2.0)));
      await tester.pump();
      // The screen renders at 200% scaling; no exception means no layout crash.
      expect(tester.takeException(), isNull);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('exposes an open source licenses page (LOW-38)',
        (tester) async {
      final c = SettingsController(erasure: FakeDataErasurePort());
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('open-source-licenses')), 200);
      expect(
          find.byKey(const ValueKey('open-source-licenses')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('open-source-licenses')));
      await tester.pumpAndSettle();
      // AboutListTile opens the standard About dialog, which carries the
      // built-in action onto the Flutter LicensePage (LOW-38). Tap the licenses
      // button regardless of its localized casing.
      expect(find.byType(AboutDialog), findsOneWidget);
      final licensesButton = find.descendant(
        of: find.byType(AboutDialog),
        matching: find.byWidgetPredicate((w) =>
            w is TextButton &&
            w.child is Text &&
            (w.child! as Text).data!.toLowerCase().contains('licen')),
      );
      expect(licensesButton, findsOneWidget);
      await tester.tap(licensesButton);
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
    });

    testWidgets('interactive elements carry Semantics labels (G4, AT-9)',
        (tester) async {
      final handle = tester.ensureSemantics();
      final c = SettingsController(erasure: FakeDataErasurePort());
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp('Privacy Mode')), findsWidgets);
      // MED-04: the caption-size slider is a single node whose accessible value
      // (from semanticFormatterCallback) names it, instead of a duplicate outer
      // Semantics(slider:) node.
      final sliderValue = tester
          .getSemantics(find.byKey(const ValueKey('caption-scale')))
          .value;
      expect(sliderValue, contains('Caption text size'));
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('strobe-toggle')), 200);
      expect(find.bySemanticsLabel(RegExp('Screen strobe and torch alert')),
          findsOneWidget);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('delete-all-data')), 200);
      expect(
          find.bySemanticsLabel(RegExp('Delete all my data')), findsOneWidget);
      handle.dispose();
    });
  });
}
