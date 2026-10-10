import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ring_captions/flutter_ring_captions.dart';

void main() {
  group('OutboundModeMachine', () {
    test('starts unprobed', () {
      final m = OutboundModeMachine();
      expect(m.state, OutboundState.unprobed);
      expect(m.hasProbed, isFalse);
      expect(m.outboundAvailable, isFalse);
    });

    test('probe success enables two-way', () {
      final m = OutboundModeMachine()..applyProbe(ProbeResult.success);
      expect(m.outboundAvailable, isTrue);
      expect(m.isCaptionsOnly, isFalse);
    });

    test('probe failure is captions-only for the session', () {
      final m = OutboundModeMachine()..applyProbe(ProbeResult.failure);
      expect(m.state, OutboundState.captionsOnlyFromProbe);
      expect(m.isCaptionsOnly, isTrue);
    });

    test('the probe result is sticky', () {
      final m = OutboundModeMachine()..applyProbe(ProbeResult.failure);
      m.applyProbe(ProbeResult.success);
      expect(m.state, OutboundState.captionsOnlyFromProbe);
    });

    test('injection failure mid-session degrades with no auto-recovery', () {
      final m = OutboundModeMachine()..applyProbe(ProbeResult.success);
      m.recordInjection(success: false);
      expect(m.state, OutboundState.captionsOnlyDegraded);
      m.recordInjection(success: true);
      expect(m.state, OutboundState.captionsOnlyDegraded);
    });

    test('injecting before the probe throws', () {
      expect(
        () => OutboundModeMachine().recordInjection(success: true),
        throwsStateError,
      );
    });

    test(
      'recordInjection in captionsOnlyFromProbe is a documented no-op (MED-22, LOW-23)',
      () {
        final m = OutboundModeMachine()..applyProbe(ProbeResult.failure);
        expect(m.state, OutboundState.captionsOnlyFromProbe);
        // A late or racing injection callback must neither throw nor change state.
        m.recordInjection(success: false);
        m.recordInjection(success: true);
        expect(m.state, OutboundState.captionsOnlyFromProbe);
      },
    );

    test(
      'recordInjection in captionsOnlyDegraded stays terminal (MED-22, LOW-23)',
      () {
        final m = OutboundModeMachine()..applyProbe(ProbeResult.success);
        m.recordInjection(success: false);
        expect(m.state, OutboundState.captionsOnlyDegraded);
        m.recordInjection(success: false);
        m.recordInjection(success: true);
        expect(m.state, OutboundState.captionsOnlyDegraded);
      },
    );

    test(
      'OutboundModeSnapshot.outboundAvailable reflects the state (MED-22)',
      () {
        expect(
          const OutboundModeSnapshot(OutboundState.twoWay).outboundAvailable,
          isTrue,
        );
        expect(
          const OutboundModeSnapshot(OutboundState.unprobed).outboundAvailable,
          isFalse,
        );
        expect(
          const OutboundModeSnapshot(
            OutboundState.captionsOnlyFromProbe,
          ).outboundAvailable,
          isFalse,
        );
      },
    );
  });
}
