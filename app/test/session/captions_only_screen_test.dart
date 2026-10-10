import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/reply/reply_bar.dart';
import 'package:threshold/session/captions_only_screen.dart';
import 'package:threshold/session/ring_app_launcher.dart';
import 'package:threshold/session/session_controller.dart';
import 'package:threshold/session/session_port.dart';

Future<(SessionController, FakeSessionPort)> _liveCaptionsOnly() async {
  final port = FakeSessionPort(probeSucceeds: false); // Captions-Only
  final c = SessionController(port: port);
  await c.open(deviceId: 'dev-1');
  return (c, port);
}

Widget _wrap(SessionController c, RingAppLauncher l) => MaterialApp(
      home: CaptionsOnlyScreen(controller: c, launcher: l),
    );

void main() {
  group('CaptionsOnlyScreen (Task 17, FR-12.1..12.4, N9; AT-6, AT-10)', () {
    testWidgets('shows the exact persistent banner text (FR-12.2)', (tester) async {
      final (c, port) = await _liveCaptionsOnly();
      await tester.pumpWidget(_wrap(c, FakeRingAppLauncher()));
      await tester.pump();
      expect(find.byKey(const ValueKey('captions-only-banner')), findsOneWidget);
      expect(
        find.text(
          'Replies unavailable on this device. You can still see what your visitor says.',
        ),
        findsOneWidget,
      );
      c.dispose();
      await port.dispose();
    });

    testWidgets('has NO reply bar (receive-only, FR-12.1)', (tester) async {
      final (c, port) = await _liveCaptionsOnly();
      await tester.pumpWidget(_wrap(c, FakeRingAppLauncher()));
      await tester.pump();
      expect(find.byType(ReplyBar), findsNothing);
      expect(find.byKey(const ValueKey('reply-bar')), findsNothing);
      // But the caption region is present (receive-only still captions).
      expect(find.byKey(const ValueKey('captions-only-region')), findsOneWidget);
      c.dispose();
      await port.dispose();
    });

    testWidgets('one-tap Open Ring app launches the Ring app (FR-12.3)', (tester) async {
      final (c, port) = await _liveCaptionsOnly();
      final launcher = FakeRingAppLauncher();
      await tester.pumpWidget(_wrap(c, launcher));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('open-ring-app')));
      await tester.pump();
      expect(launcher.launchCalls, 1);
      c.dispose();
      await port.dispose();
    });

    testWidgets('banner text is dash-free (NFR-10)', (tester) async {
      expect(kCaptionsOnlyBanner.contains('\u2014'), isFalse);
      expect(kCaptionsOnlyBanner.contains('\u2013'), isFalse);
    });

    testWidgets('the session runs Captions-Only when the probe failed (AT-6)', (tester) async {
      final (c, port) = await _liveCaptionsOnly();
      expect(c.isCaptionsOnly, isTrue);
      expect(c.outboundAvailable, isFalse);
      c.dispose();
      await port.dispose();
    });

    testWidgets('End control tears the session down (regression under AT-10)', (tester) async {
      final (c, port) = await _liveCaptionsOnly();
      await tester.pumpWidget(_wrap(c, FakeRingAppLauncher()));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('captions-only-end')));
      await tester.pumpAndSettle();
      expect(port.closeCalls, 1);
      c.dispose();
      await port.dispose();
    });

    testWidgets('controls and banner carry Semantics labels (G4, AT-10)', (tester) async {
      final handle = tester.ensureSemantics();
      final (c, port) = await _liveCaptionsOnly();
      await tester.pumpWidget(_wrap(c, FakeRingAppLauncher()));
      await tester.pump();
      expect(find.bySemanticsLabel('Open Ring app'), findsOneWidget);
      expect(find.bySemanticsLabel('End session'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Replies unavailable')), findsOneWidget);
      handle.dispose();
      c.dispose();
      await port.dispose();
    });

    testWidgets('a reconnecting session shows the shared status, not the live layout (MED-07)',
        (tester) async {
      final (c, port) = await _liveCaptionsOnly();
      await tester.pumpWidget(_wrap(c, FakeRingAppLauncher()));
      await tester.pump();
      // Drop the connection: the session enters reconnecting.
      port.emit(SessionPortEvent.dropped);
      await tester.pump(); // deliver the stream event
      await tester.pump(); // rebuild from the controller notification
      expect(c.state.toString(), contains('reconnecting'));
      // The receive-only banner is gone; the shared reconnecting panel shows.
      expect(find.byKey(const ValueKey('captions-only-banner')), findsNothing);
      expect(find.byKey(const ValueKey('status-reconnecting')), findsOneWidget);
      c.dispose();
      await port.dispose();
    });

    testWidgets('a failed Open Ring app launch shows the store fallback (MED-07)',
        (tester) async {
      final (c, port) = await _liveCaptionsOnly();
      // The Ring app is not installed.
      await tester.pumpWidget(_wrap(c, FakeRingAppLauncher(canLaunch: false)));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('open-ring-app')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ring-app-fallback')), findsOneWidget);
      expect(find.textContaining('install it from your app store'), findsOneWidget);
      c.dispose();
      await port.dispose();
    });
  });
}
