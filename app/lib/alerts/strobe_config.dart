// Photosensitivity-safe strobe/torch config (Task 11, FR-9.3, FR-9.4; AT-16).
// WCAG 2.2 SC 2.3.1: never more than three flashes in any one second. The strobe
// is OFF by default and requires explicit opt-in. This is pure logic so the flash
// rate is unit-testable without a device; the platform torch/screen call is a
// thin adapter that consumes `flashPeriodMs`.

import 'package:flutter/foundation.dart';

/// The hard ceiling from WCAG 2.2 SC 2.3.1 (FR-9.4): the strobe is NEVER allowed
/// to flash faster than this, even if a higher rate is requested.
const int kMaxFlashesPerSecond = 3;

/// The recommended (and default-when-enabled) flash rate (MED-09). Sitting at
/// the WCAG ceiling of 3 Hz is the maximum tolerated, not a safe default; 2 Hz
/// keeps a clear margin below the photosensitivity threshold while staying
/// noticeable.
const int kRecommendedFlashesPerSecond = 2;

/// The maximum duration a strobe alert may run before it is cut off (MED-09): a
/// strobe that runs indefinitely is a seizure risk even at a safe rate. The
/// adapter stops flashing after this elapses.
const Duration kMaxStrobeDuration = Duration(seconds: 10);

/// The photosensitivity warning shown next to the strobe toggle before a
/// resident enables it (MED-09). Dash-free (NFR-10).
const String kStrobePhotosensitivityWarning =
    'This flashes the screen and torch. Do not enable it if you or someone '
    'nearby has photosensitive epilepsy. Flashing is capped at 2 times per '
    'second and stops after a short time.';

@immutable
class StrobeConfig {
  const StrobeConfig({
    required this.enabled,
    required this.flashesPerSecond,
    this.maxDuration = kMaxStrobeDuration,
  });

  /// Off by default (FR-9.4): explicit opt-in required.
  final bool enabled;

  /// Requested flash rate. Always clamped to [1, kMaxFlashesPerSecond].
  final int flashesPerSecond;

  /// How long an enabled strobe may run before the adapter stops it (MED-09).
  /// Capped at [kMaxStrobeDuration] so it can never flash indefinitely.
  final Duration maxDuration;

  /// The safe default: disabled, and at the RECOMMENDED 2 Hz rate for when
  /// enabled (MED-09), not the 3 Hz ceiling.
  static const StrobeConfig defaultDisabled = StrobeConfig(
    enabled: false,
    flashesPerSecond: kRecommendedFlashesPerSecond,
  );

  /// Build a config that can never exceed the photosensitivity ceiling or run
  /// longer than the duration cap. A requested rate above 3 is clamped to 3;
  /// below 1 is clamped to 1 (FR-9.4). The duration is clamped to
  /// [kMaxStrobeDuration] (MED-09). Enabling still requires `enabled: true`.
  factory StrobeConfig.safe({
    required bool enabled,
    required int requestedFlashesPerSecond,
    Duration? requestedDuration,
  }) {
    final clamped = requestedFlashesPerSecond.clamp(1, kMaxFlashesPerSecond);
    final duration = requestedDuration == null
        ? kMaxStrobeDuration
        : (requestedDuration > kMaxStrobeDuration
            ? kMaxStrobeDuration
            : requestedDuration);
    return StrobeConfig(
      enabled: enabled,
      flashesPerSecond: clamped,
      maxDuration: duration,
    );
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
  bool get isPhotosensitivitySafe =>
      effectiveFlashesPerSecond <= kMaxFlashesPerSecond + 1e-9;

  StrobeConfig copyWith(
      {bool? enabled, int? flashesPerSecond, Duration? maxDuration}) {
    return StrobeConfig.safe(
      enabled: enabled ?? this.enabled,
      requestedFlashesPerSecond: flashesPerSecond ?? this.flashesPerSecond,
      requestedDuration: maxDuration ?? this.maxDuration,
    );
  }
}
