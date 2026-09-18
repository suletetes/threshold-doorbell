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
      expect(() => OutboundModeMachine().recordInjection(success: true), throwsStateError);
    });
  });
}
