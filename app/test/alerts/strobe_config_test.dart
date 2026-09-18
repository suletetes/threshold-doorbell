import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/alerts/strobe_config.dart';

void main() {
  group('StrobeConfig photosensitivity safety (FR-9.4, AT-16)', () {
    test('is off by default (explicit opt-in required)', () {
      expect(StrobeConfig.defaultDisabled.enabled, isFalse);
    });

    test('never exceeds 3 flashes per second, even when a higher rate is requested', () {
      for (final requested in [4, 5, 10, 60, 1000]) {
        final cfg = StrobeConfig.safe(enabled: true, requestedFlashesPerSecond: requested);
        expect(cfg.flashesPerSecond, kMaxFlashesPerSecond);
        expect(cfg.effectiveFlashesPerSecond, lessThanOrEqualTo(kMaxFlashesPerSecond.toDouble()));
        expect(cfg.isPhotosensitivitySafe, isTrue);
      }
    });

    test('clamps a below-minimum rate up to 1', () {
      final cfg = StrobeConfig.safe(enabled: true, requestedFlashesPerSecond: 0);
      expect(cfg.flashesPerSecond, 1);
    });

    test('measured flash rate from the period never exceeds the ceiling', () {
      for (final requested in [1, 2, 3, 99]) {
        final cfg = StrobeConfig.safe(enabled: true, requestedFlashesPerSecond: requested);
        // A device would flash once per flashPeriodMs; assert that rate is safe.
        final measured = 1000 / cfg.flashPeriodMs;
        expect(measured, lessThanOrEqualTo(kMaxFlashesPerSecond + 1e-9));
      }
    });

    test('copyWith re-clamps the rate', () {
      final cfg = StrobeConfig.defaultDisabled.copyWith(enabled: true, flashesPerSecond: 50);
      expect(cfg.enabled, isTrue);
      expect(cfg.flashesPerSecond, kMaxFlashesPerSecond);
    });

    test('flashPeriodMs is at least 333 ms (3 per second)', () {
      final cfg = StrobeConfig.safe(enabled: true, requestedFlashesPerSecond: 3);
      expect(cfg.flashPeriodMs, greaterThanOrEqualTo(333));
    });
  });
}
