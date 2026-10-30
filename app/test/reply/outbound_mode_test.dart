import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/reply/outbound_mode.dart';

void main() {
  group('OutboundModeMachine reset (same instance re-probes, FR-6.4b)', () {
    test('reset returns to unprobed so a new session re-probes in place', () {
      final m = OutboundModeMachine();
      m.applyProbe(ProbeResult.failure); // session 1: captions-only
      expect(m.outboundAvailable, isFalse);
      expect(m.isCaptionsOnly, isTrue);

      // A new session resets the SAME instance (the reply controller holds this
      // reference), then re-probes. It must now reflect the new probe, not the
      // stale captions-only result.
      m.reset();
      expect(m.hasProbed, isFalse);
      expect(m.outboundAvailable, isFalse);
      m.applyProbe(ProbeResult.success);
      expect(m.outboundAvailable, isTrue, reason: 'reset instance re-probes');
      expect(m.isCaptionsOnly, isFalse);
    });
  });

  group('OutboundModeMachine (Task 16, FR-6.4, 6.4a, 6.4b; AT-6)', () {
    test('starts unprobed with no outbound and not captions-only', () {
      final m = OutboundModeMachine();
      expect(m.state, OutboundState.unprobed);
      expect(m.hasProbed, isFalse);
      expect(m.outboundAvailable, isFalse);
      expect(m.isCaptionsOnly, isFalse);
    });

    test('probe success enables two-way for the session', () {
      final m = OutboundModeMachine()..applyProbe(ProbeResult.success);
      expect(m.state, OutboundState.twoWay);
      expect(m.outboundAvailable, isTrue);
      expect(m.isCaptionsOnly, isFalse);
    });

    test(
        'probe failure at start is Captions-Only for the whole session (FR-6.4a, AT-6)',
        () {
      final m = OutboundModeMachine()..applyProbe(ProbeResult.failure);
      expect(m.state, OutboundState.captionsOnlyFromProbe);
      expect(m.outboundAvailable, isFalse);
      expect(m.isCaptionsOnly, isTrue);
    });

    test('the probe result is sticky: a re-probe is ignored (FR-6.4b)', () {
      final m = OutboundModeMachine()..applyProbe(ProbeResult.failure);
      // A later success must NOT flip a failed session to two-way.
      m.applyProbe(ProbeResult.success);
      expect(m.state, OutboundState.captionsOnlyFromProbe);
      expect(m.outboundAvailable, isFalse);
    });

    test('a re-probe cannot downgrade a successful session either', () {
      final m = OutboundModeMachine()..applyProbe(ProbeResult.success);
      m.applyProbe(ProbeResult.failure);
      expect(m.state, OutboundState.twoWay);
    });

    test(
        'injection failure mid-session degrades to Captions-Only, no auto-recovery (FR-6.4b, AT-6)',
        () {
      final m = OutboundModeMachine()..applyProbe(ProbeResult.success);
      m.recordInjection(success: true); // works once
      expect(m.state, OutboundState.twoWay);
      m.recordInjection(success: false); // then fails
      expect(m.state, OutboundState.captionsOnlyDegraded);
      expect(m.outboundAvailable, isFalse);
      expect(m.isCaptionsOnly, isTrue);
      // No auto-recovery: a subsequent success does NOT restore two-way.
      m.recordInjection(success: true);
      expect(m.state, OutboundState.captionsOnlyDegraded);
      expect(m.outboundAvailable, isFalse);
    });

    test(
        'injection failure while already Captions-Only (from probe) is a no-op',
        () {
      final m = OutboundModeMachine()..applyProbe(ProbeResult.failure);
      m.recordInjection(success: false);
      expect(m.state, OutboundState.captionsOnlyFromProbe);
    });

    test('successful injections keep the session two-way', () {
      final m = OutboundModeMachine()..applyProbe(ProbeResult.success);
      for (var i = 0; i < 5; i++) {
        m.recordInjection(success: true);
      }
      expect(m.state, OutboundState.twoWay);
      expect(m.outboundAvailable, isTrue);
    });

    test('injecting before the probe throws (probe gates the reply bar)', () {
      final m = OutboundModeMachine();
      expect(() => m.recordInjection(success: true), throwsStateError);
    });

    test('a new session re-probes from scratch (FR-6.4b)', () {
      // Session 1 degraded.
      final s1 = OutboundModeMachine()..applyProbe(ProbeResult.success);
      s1.recordInjection(success: false);
      expect(s1.isCaptionsOnly, isTrue);
      // Session 2 is a fresh instance and probes anew, succeeding this time.
      final s2 = OutboundModeMachine()..applyProbe(ProbeResult.success);
      expect(s2.outboundAvailable, isTrue);
      expect(s2.isCaptionsOnly, isFalse);
    });
  });
}
