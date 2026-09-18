// Photosensitivity-safe strobe/torch config (Task 11, FR-9.3, FR-9.4; AT-16).
// WCAG 2.2 SC 2.3.1: never more than three flashes in any one second. The strobe
// is OFF by default and requires explicit opt-in. This is pure logic so the flash
// rate is unit-testable without a device; the platform torch/screen call is a
// thin adapter that consumes `flashPeriodMs`.

import 'package:flutter/foundation.dart';

/// The hard ceiling from WCAG 2.2 SC 2.3.1 (FR-9.4).
const int kMaxFlashesPerSecond = 3;

@immutable
class StrobeConfig {
  const StrobeConfig({required this.enabled, required this.flashesPerSecond});

  /// Off by default (FR-9.4): explicit opt-in required.
  final bool enabled;

  /// Requested flash rate. Always clamped to [1, kMaxFlashesPerSecond].
  final int flashesPerSecond;

  /// The safe default: disabled, and at the ceiling rate for when enabled.
  static const StrobeConfig defaultDisabled = StrobeConfig(
    enabled: false,
    flashesPerSecond: kMaxFlashesPerSecond,
  );

  /// Build a config that can never exceed the photosensitivity ceiling.
  /// A requested rate above 3 is clamped to 3; below 1 is clamped to 1
  /// (FR-9.4). Enabling still requires an explicit `enabled: true`.
  factory StrobeConfig.safe({required bool enabled, required int requestedFlashesPerSecond}) {
    final clamped = requestedFlashesPerSecond.clamp(1, kMaxFlashesPerSecond);
    return StrobeConfig(enabled: enabled, flashesPerSecond: clamped);
  }

  /// The on/off period of a single flash cycle in milliseconds. With N flashes
  /// per second the full cycle is 1000/N ms. We round the period UP (ceil) so the
  /// realized rate is never faster than requested: rounding down would shorten
  /// the period and push the effective rate above the WCAG ceiling (FR-9.4).
  int get flashPeriodMs => (1000 / flashesPerSecond).ceil();

  /// The measured flash rate an adapter would produce from `flashPeriodMs`. Used
  /// by the AT-16 test to assert the effective rate never exceeds the ceiling.
  double get effectiveFlashesPerSecond => 1000 / flashPeriodMs;

  /// True when the effective rate is within the WCAG ceiling (always, by
  /// construction, but asserted defensively).
  bool get isPhotosensitivitySafe => effectiveFlashesPerSecond <= kMaxFlashesPerSecond + 1e-9;

  StrobeConfig copyWith({bool? enabled, int? flashesPerSecond}) {
    return StrobeConfig.safe(
      enabled: enabled ?? this.enabled,
      requestedFlashesPerSecond: flashesPerSecond ?? this.flashesPerSecond,
    );
  }
}
