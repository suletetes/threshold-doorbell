import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/session/auth_port.dart';
import 'package:threshold/session/conversation_screen.dart';
import 'package:threshold/session/session_controller.dart';
import 'package:threshold/session/session_port.dart';
import 'package:threshold/session/session_state.dart';
import 'package:threshold/session/watermark_safe_area.dart';

Widget _wrap(SessionController c) =>
    MaterialApp(home: ConversationScreen(controller: c));

void main() {
  group('ConversationScreen states (Task 12; AT-3, AT-12, AT-25)', () {
    testWidgets('renders the live overlay with caption region and end control',
        (tester) async {
      final port = FakeSessionPort();
      final c = SessionController(port: port);
      await c.open(deviceId: 'dev-1');
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      expect(find.byKey(const ValueKey('caption-region')), findsOneWidget);
      expect(find.byKey(const ValueKey('end-session')), findsOneWidget);
      expect(find.byKey(const ValueKey('mode-badge')), findsOneWidget);
      c.dispose();
      await port.dispose();
    });

    testWidgets('shows the connecting panel while the connect is pending',
        (tester) async {
      // Hold connect open with a gate so the controller stays in the
      // connecting state while we pump and inspect the UI. Reverting the
      // ConversationScreen so it no longer renders the connecting panel (or the
      // controller so open() skips the connecting state) fails this test.
      final gate = Completer<void>();
      final port = FakeSessionPort(connectGate: gate.future);
      final c = SessionController(port: port);
      final future = c.open(deviceId: 'dev-1');
      await tester.pumpWidget(_wrap(c));
      await tester.pump();

      // The connecting panel is on screen with its user-facing copy, and the
      // live caption region is not yet present.
      expect(c.state, SessionState.connecting);
      expect(find.byKey(const ValueKey('status-connecting')), findsOneWidget);
      expect(find.text('Connecting to your doorbell'), findsOneWidget);
      expect(find.byKey(const ValueKey('caption-region')), findsNothing);

      // Releasing the gate lets the session reach live.
      gate.complete();
      await future;
      await tester.pumpAndSettle();
      expect(c.state, SessionState.live);
      expect(find.byKey(const ValueKey('status-connecting')), findsNothing);
      expect(find.byKey(const ValueKey('caption-region')), findsOneWidget);
      c.dispose();
      await port.dispose();
    });

    testWidgets('error state shows a dash-free message', (tester) async {
      final port = FakeSessionPort(
        connectPlan: <ConnectPlan>[ConnectPlan.fail, ConnectPlan.fail],
      );
      final c = SessionController(port: port);
      await c.open(deviceId: 'dev-1');
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      expect(find.byKey(const ValueKey('status-error')), findsOneWidget);
      expect(find.text("Couldn't connect to your doorbell."), findsOneWidget);
      c.dispose();
      await port.dispose();
    });

    testWidgets('backgrounded state shows the paused panel (AT-25)',
        (tester) async {
      final port = FakeSessionPort();
      final c = SessionController(port: port);
      await c.open(deviceId: 'dev-1');
      c.onBackgrounded();
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      expect(find.byKey(const ValueKey('status-backgrounded')), findsOneWidget);
      c.dispose();
      await port.dispose();
    });

    testWidgets('the auth-recovery modal blocks semantics behind it (MED-05)',
        (tester) async {
      final port = FakeSessionPort();
      final c = SessionController(port: port);
      await c.open(deviceId: 'dev-1');
      c.beginAuthRecovery();
      await tester.pumpWidget(
        MaterialApp(
            home: ConversationScreen(controller: c, authPort: FakeAuthPort())),
      );
      await tester.pump();
      // A BlockSemantics wraps the modal so a screen reader cannot reach the
      // End / Reply controls underneath it (MED-05). The auth-recovery prompt
      // card is a descendant of a BlockSemantics.
      expect(
          find.byKey(const ValueKey('auth-recovery-prompt')), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('auth-recovery-prompt')),
          matching: find.byType(BlockSemantics),
        ),
        findsOneWidget,
      );
      c.dispose();
      await port.dispose();
    });

    testWidgets('sign in resumes only after a verified token (AT-12, HIGH-09)',
        (tester) async {
      final port = FakeSessionPort();
      final auth = FakeAuthPort(plan: <AuthResult>[AuthResult.verified]);
      final c = SessionController(port: port);
      await c.open(deviceId: 'dev-1');
      c.beginAuthRecovery();
      await tester.pumpWidget(
        MaterialApp(home: ConversationScreen(controller: c, authPort: auth)),
      );
      await tester.pump();
      expect(
          find.byKey(const ValueKey('auth-recovery-prompt')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('auth-recovery-signin')));
      await tester.pumpAndSettle();
      // The real auth port was consulted and only a verified token resumed.
      expect(auth.attempts, 1);
      expect(find.byKey(const ValueKey('auth-recovery-prompt')), findsNothing);
      expect(c.state, SessionState.live);
      c.dispose();
      await port.dispose();
    });

    testWidgets(
        'a failed re-authentication does NOT resume the session (HIGH-09)',
        (tester) async {
      final port = FakeSessionPort();
      final auth = FakeAuthPort(plan: <AuthResult>[AuthResult.failed]);
      final c = SessionController(port: port);
      await c.open(deviceId: 'dev-1');
      c.beginAuthRecovery();
      await tester.pumpWidget(
        MaterialApp(home: ConversationScreen(controller: c, authPort: auth)),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('auth-recovery-signin')));
      await tester.pumpAndSettle();
      // A failed token tears the session down rather than resuming it live.
      expect(auth.attempts, 1);
      expect(c.state, isNot(SessionState.live));
      c.dispose();
      await port.dispose();
    });

    testWidgets('tapping End closes the session', (tester) async {
      final port = FakeSessionPort();
      final c = SessionController(port: port);
      await c.open(deviceId: 'dev-1');
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('end-session')));
      await tester.pumpAndSettle();
      expect(port.closeCalls, 1);
      c.dispose();
      await port.dispose();
    });

    testWidgets(
        'live status region and video surface carry Semantics labels (G4)',
        (tester) async {
      final handle = tester.ensureSemantics();
      final port = FakeSessionPort();
      final c = SessionController(port: port);
      await c.open(deviceId: 'dev-1');
      await tester.pumpWidget(_wrap(c));
      await tester.pump();
      expect(
        find.bySemanticsLabel('Live video from your doorbell'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('Visitor captions')), findsOneWidget);
      expect(find.bySemanticsLabel('End session'), findsOneWidget);
      handle.dispose();
      c.dispose();
      await port.dispose();
    });
  });

  group('Watermark safe overlay geometry (Task 12, FR-4.5)', () {
    test('safe insets clear the watermark band', () {
      final insets = watermarkSafeInsets();
      expect(insets.top, kWatermarkBandHeight);
    });

    test('an overlay anchored below the band clears both corners', () {
      const size = Size(400, 800);
      const overlay = Rect.fromLTWH(0, kWatermarkBandHeight, 400, 200);
      expect(clearsWatermarkCorners(overlay, size), isTrue);
    });

    test('an overlay in the top-left corner collides (FR-4.5)', () {
      const size = Size(400, 800);
      const overlay = Rect.fromLTWH(0, 0, 80, 40);
      expect(clearsWatermarkCorners(overlay, size), isFalse);
    });

    test('an overlay in the top-right corner collides (FR-4.5)', () {
      const size = Size(400, 800);
      const overlay = Rect.fromLTWH(340, 0, 60, 40);
      expect(clearsWatermarkCorners(overlay, size), isFalse);
    });
  });
}
