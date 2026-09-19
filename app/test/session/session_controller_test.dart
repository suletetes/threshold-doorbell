import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/session/session_concurrency.dart';
import 'package:threshold/session/session_controller.dart';
import 'package:threshold/session/session_port.dart';
import 'package:threshold/session/session_state.dart';

void main() {
  group('SessionController lifecycle (Task 12, FR-4.1..4.4; AT-3)', () {
    test('open goes CONNECTING -> PROBING -> LIVE and negotiates ARCH-1 media', () async {
      final port = FakeSessionPort();
      final c = SessionController(port: port);
      await c.open(deviceId: 'dev-1');
      expect(c.state, SessionState.live);
      expect(port.connectCalls, 1);
      expect(port.probeCalls, 1);
      // AT-3: exactly one peer connection, audio sendrecv, video recvonly.
      expect(c.negotiatedMedia!.isArch1Compliant, isTrue);
      expect(c.negotiatedMedia!.audioDirection, 'sendrecv');
      expect(c.negotiatedMedia!.videoDirection, 'recvonly');
      expect(c.negotiatedMedia!.peerConnectionCount, 1);
      c.dispose();
      await port.dispose();
    });

    test('probe success enables two-way; probe failure yields Captions-Only (AT-6 wiring)', () async {
      final okPort = FakeSessionPort(probeSucceeds: true);
      final okC = SessionController(port: okPort);
      await okC.open(deviceId: 'dev-1');
      expect(okC.outboundAvailable, isTrue);
      expect(okC.isCaptionsOnly, isFalse);

      final failPort = FakeSessionPort(probeSucceeds: false);
      final failC = SessionController(port: failPort);
      await failC.open(deviceId: 'dev-1');
      expect(failC.outboundAvailable, isFalse);
      expect(failC.isCaptionsOnly, isTrue);
      okC.dispose();
      failC.dispose();
      await okPort.dispose();
      await failPort.dispose();
    });

    test('one failed attempt then success stays under the retry budget (FR-4.4)', () async {
      final port = FakeSessionPort(
        connectPlan: <ConnectPlan>[ConnectPlan.fail, ConnectPlan.succeed],
      );
      final c = SessionController(port: port);
      await c.open(deviceId: 'dev-1');
      expect(c.state, SessionState.live);
      expect(port.connectCalls, 2);
      c.dispose();
      await port.dispose();
    });

    test('two failed attempts go to ERROR with a dash-free message (FR-4.4)', () async {
      final port = FakeSessionPort(
        connectPlan: <ConnectPlan>[ConnectPlan.fail, ConnectPlan.fail],
      );
      final c = SessionController(port: port);
      await c.open(deviceId: 'dev-1');
      expect(c.state, SessionState.error);
      expect(c.connectAttempts, kMaxConnectAttempts);
      expect(c.snapshot.errorMessage, "Couldn't connect to your doorbell.");
      expect(c.snapshot.errorMessage!.contains('\u2014'), isFalse);
      expect(c.snapshot.errorMessage!.contains('\u2013'), isFalse);
      c.dispose();
      await port.dispose();
    });

    test('a fresh session re-probes from scratch (FR-6.4b)', () async {
      final port = FakeSessionPort(probeSucceeds: true);
      final c = SessionController(port: port);
      await c.open(deviceId: 'dev-1');
      c.recordInjection(success: false); // degrade this session
      expect(c.isCaptionsOnly, isTrue);
      await c.end();
      // New session: probe succeeds anew.
      await c.open(deviceId: 'dev-1');
      expect(c.outboundAvailable, isTrue);
      expect(c.isCaptionsOnly, isFalse);
      c.dispose();
      await port.dispose();
    });

    test('end closes the port and returns to idle (FR-4.3)', () async {
      final port = FakeSessionPort();
      final c = SessionController(port: port);
      await c.open(deviceId: 'dev-1');
      await c.end();
      expect(c.state, SessionState.idle);
      expect(port.closeCalls, 1);
      c.dispose();
      await port.dispose();
    });

    test('opening while active throws (exactly one live session, FR-4.6/4.7)', () async {
      final port = FakeSessionPort();
      final c = SessionController(port: port);
      await c.open(deviceId: 'dev-1');
      expect(() => c.open(deviceId: 'dev-2'), throwsStateError);
      c.dispose();
      await port.dispose();
    });
  });

  group('Concurrency (Task 12, FR-4.6, FR-4.7; AT-11)', () {
    test('no active session: event may open', () {
      final d = decideConcurrency(activeDeviceId: null, eventDeviceId: 'dev-1');
      expect(d.action, ConcurrencyAction.openAllowed);
      expect(d.replayHaptic, isFalse);
    });

    test('same device updates context and replays haptic, no second session (FR-4.6)', () async {
      final port = FakeSessionPort();
      final c = SessionController(port: port);
      await c.open(deviceId: 'dev-1');
      final d = c.onIncomingEvent(eventDeviceId: 'dev-1', eventType: 'person_detected');
      expect(d.action, ConcurrencyAction.updateContextSameDevice);
      expect(d.replayHaptic, isTrue);
      expect(c.sameDeviceHapticReplays, 1);
      expect(c.queuedEvents, isEmpty);
      expect(c.state, SessionState.live); // still one session
      c.dispose();
      await port.dispose();
    });

    test('different device queues as a notification, does not interrupt (FR-4.7)', () async {
      final port = FakeSessionPort();
      final c = SessionController(port: port);
      await c.open(deviceId: 'dev-1');
      final d = c.onIncomingEvent(eventDeviceId: 'dev-2', eventType: 'motion_detected');
      expect(d.action, ConcurrencyAction.queueDifferentDevice);
      expect(d.replayHaptic, isFalse);
      expect(c.queuedEvents.length, 1);
      expect(c.queuedEvents.single.deviceId, 'dev-2');
      expect(c.state, SessionState.live); // uninterrupted
      c.dispose();
      await port.dispose();
    });
  });

  group('Background survival (Task 12, FR-4.3a; AT-25)', () {
    test('backgrounding under 5 minutes preserves and resumes the session', () async {
      var now = 0;
      final port = FakeSessionPort();
      final c = SessionController(port: port, nowMs: () => now);
      await c.open(deviceId: 'dev-1');
      c.onBackgrounded();
      expect(c.state, SessionState.backgrounded);
      now += const Duration(minutes: 4).inMilliseconds; // within window
      c.tickBackground();
      expect(c.state, SessionState.backgrounded); // still alive
      c.onForegrounded();
      expect(c.state, SessionState.live); // resumed without renegotiation
      expect(port.closeCalls, 0);
      c.dispose();
      await port.dispose();
    });

    test('background beyond 5 minutes closes and releases the session URL', () async {
      var now = 0;
      final port = FakeSessionPort();
      final c = SessionController(port: port, nowMs: () => now);
      await c.open(deviceId: 'dev-1');
      c.onBackgrounded();
      now += const Duration(minutes: 5, seconds: 1).inMilliseconds; // beyond window
      c.tickBackground();
      // Close is fire-and-forget; allow the microtask to run.
      await Future<void>.delayed(Duration.zero);
      expect(c.state, SessionState.idle);
      expect(port.closeCalls, 1);
      c.dispose();
      await port.dispose();
    });

    test('foregrounding after the window closes the session', () async {
      var now = 0;
      final port = FakeSessionPort();
      final c = SessionController(port: port, nowMs: () => now);
      await c.open(deviceId: 'dev-1');
      c.onBackgrounded();
      now += const Duration(minutes: 6).inMilliseconds;
      c.onForegrounded();
      await Future<void>.delayed(Duration.zero);
      expect(c.state, SessionState.idle);
      expect(port.closeCalls, 1);
      c.dispose();
      await port.dispose();
    });
  });

  group('Reconnect (Task 12, design §5.2)', () {
    test('a drop enters RECONNECTING; reconnected returns to LIVE', () async {
      final port = FakeSessionPort();
      final c = SessionController(port: port);
      await c.open(deviceId: 'dev-1');
      port.emit(SessionPortEvent.dropped);
      await Future<void>.delayed(Duration.zero);
      expect(c.state, SessionState.reconnecting);
      port.emit(SessionPortEvent.reconnected);
      await Future<void>.delayed(Duration.zero);
      expect(c.state, SessionState.live);
      c.dispose();
      await port.dispose();
    });

    test('two reconnect failures go to CLOSING then IDLE', () async {
      final port = FakeSessionPort();
      final c = SessionController(port: port);
      await c.open(deviceId: 'dev-1');
      port.emit(SessionPortEvent.dropped);
      await Future<void>.delayed(Duration.zero);
      port.emit(SessionPortEvent.reconnectFailed);
      await Future<void>.delayed(Duration.zero);
      expect(c.state, SessionState.reconnecting);
      port.emit(SessionPortEvent.reconnectFailed);
      await Future<void>.delayed(Duration.zero);
      expect(c.state, SessionState.idle);
      expect(port.closeCalls, 1);
      c.dispose();
      await port.dispose();
    });
  });

  group('Unified auth recovery (Task 12, FR-1.5, FR-4.8; AT-12)', () {
    test('session expiry enters authRecovering, preserving the prior state', () async {
      final port = FakeSessionPort();
      final c = SessionController(port: port);
      await c.open(deviceId: 'dev-1');
      port.emit(SessionPortEvent.authExpired);
      await Future<void>.delayed(Duration.zero);
      expect(c.state, SessionState.authRecovering);
      expect(c.snapshot.stateBeforeAuthRecovery, SessionState.live);
      c.dispose();
      await port.dispose();
    });

    test('exactly one recovery prompt: a second expiry does not stack (AT-12)', () async {
      final port = FakeSessionPort();
      final c = SessionController(port: port);
      await c.open(deviceId: 'dev-1');
      port.emit(SessionPortEvent.authExpired);
      await Future<void>.delayed(Duration.zero);
      final preserved = c.snapshot.stateBeforeAuthRecovery;
      port.emit(SessionPortEvent.authExpired); // second expiry
      await Future<void>.delayed(Duration.zero);
      expect(c.state, SessionState.authRecovering);
      // The preserved state is not overwritten by the second event.
      expect(c.snapshot.stateBeforeAuthRecovery, preserved);
      c.dispose();
      await port.dispose();
    });

    test('successful recovery resumes the preserved state and the action', () async {
      final port = FakeSessionPort();
      final c = SessionController(port: port);
      await c.open(deviceId: 'dev-1');
      c.beginAuthRecovery();
      c.completeAuthRecovery(success: true);
      expect(c.state, SessionState.live); // resumed
      c.dispose();
      await port.dispose();
    });

    test('declined recovery tears the session down cleanly', () async {
      final port = FakeSessionPort();
      final c = SessionController(port: port);
      await c.open(deviceId: 'dev-1');
      c.beginAuthRecovery();
      c.completeAuthRecovery(success: false);
      await Future<void>.delayed(Duration.zero);
      expect(c.state, SessionState.idle);
      expect(port.closeCalls, 1);
      c.dispose();
      await port.dispose();
    });
  });
}
