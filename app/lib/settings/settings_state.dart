// Settings state (Task 24, FR-8.5, FR-8.6, FR-10.1..FR-10.4, FR-14.1, NFR-2;
// AT-9). Immutable settings model plus bounded caption size and contrast whose
// minimum contrast is the 4.5:1 floor (FR-10.2), the three haptic toggles, the
// off-by-default strobe (FR-9.4), language, and the 90-day retention display
// (FR-8.5). The caption-mode switch applies to the next session (FR-10.1), so
// the model records both the active and the pending mode. Pure so bounds and the
// contrast floor are unit-testable.

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../alerts/haptic_vocabulary.dart';
import '../captions/language_selection.dart';
import 'contrast.dart';

/// The caption size scale bounds (FR-10.2 bounded range). 1.0 is default; up to
/// 2.0 supports the 200% dynamic-type requirement (NFR-2).
const double kMinCaptionScale = 1.0;
const double kMaxCaptionScale = 2.0;

/// The retention period shown in Settings (FR-8.5): 90 days.
const int kRetentionDays = 90;

@immutable
class ThresholdSettings {
  ThresholdSettings({
    required this.activeMode,
    required this.pendingMode,
    required double captionScale,
    required Color captionForeground,
    required Color captionBackground,
    required Map<HapticEvent, bool> hapticEnabled,
    required this.strobeEnabled,
    required this.language,
    required this.audibleNoticeEnabled,
  })  : captionScale = captionScale.clamp(kMinCaptionScale, kMaxCaptionScale),
        // Reject a translucent caption background (HIGH-07): a see-through
        // background lets inbound video bleed through the surface the 4.5:1
        // floor is computed against, so the ratio could not be guaranteed. The
        // background is forced opaque before the floor is enforced against it.
        captionBackground = forceOpaque(captionBackground),
        // The floor is enforced in code so no setting can breach NFR-2 (FR-10.2),
        // against the now-opaque background.
        captionForeground =
            enforceContrastFloor(captionForeground, forceOpaque(captionBackground)),
        // Store an unmodifiable copy so the value type cannot be mutated in
        // place after construction (LOW-06): the map was previously held by
        // reference, letting a caller mutate "immutable" settings.
        hapticEnabled =
            Map<HapticEvent, bool>.unmodifiable(Map<HapticEvent, bool>.from(hapticEnabled));

  /// The mode the current/next session uses. The switch applies to the NEXT
  /// session (FR-10.1); [pendingMode] holds a queued change until then.
  final CaptionMode activeMode;
  final CaptionMode pendingMode;

  /// Caption text scale, clamped to [1.0, 2.0] (FR-10.2, NFR-2).
  final double captionScale;

  /// Caption colors. [captionForeground] is guaranteed to meet the 4.5:1 floor
  /// against [captionBackground] (FR-10.2, NFR-2).
  final Color captionForeground;
  final Color captionBackground;

  /// Per-pattern haptic enable flags (FR-10.3). Keyed by the three events.
  final Map<HapticEvent, bool> hapticEnabled;

  /// Screen strobe / torch, off by default (FR-9.4).
  final bool strobeEnabled;

  /// Recognition language (BCP-47), FR-16.
  final String language;

  /// Optional audible door notice, off by default (FR-14.3).
  final bool audibleNoticeEnabled;

  /// The measured caption contrast ratio (>= 4.5 by construction, FR-10.2).
  double get captionContrastRatio =>
      contrastRatio(captionForeground, captionBackground);

  /// Whether the caption contrast meets the floor (always true by construction).
  bool get meetsContrastFloor =>
      captionContrastRatio >= kContrastFloor - 1e-9;

  /// The retention period text (FR-8.5). Dash-free (NFR-10).
  String get retentionLabel => 'Transcripts are kept for $kRetentionDays days, then deleted.';

  /// Value equality (LOW-06): two settings with the same fields are equal, so a
  /// provider can skip a no-op rebuild and tests can assert settings round-trip
  /// through persistence unchanged. The haptic map compares by content.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ThresholdSettings &&
        other.activeMode == activeMode &&
        other.pendingMode == pendingMode &&
        other.captionScale == captionScale &&
        other.captionForeground == captionForeground &&
        other.captionBackground == captionBackground &&
        const MapEquality<HapticEvent, bool>().equals(other.hapticEnabled, hapticEnabled) &&
        other.strobeEnabled == strobeEnabled &&
        other.language == language &&
        other.audibleNoticeEnabled == audibleNoticeEnabled;
  }

  @override
  int get hashCode => Object.hash(
        activeMode,
        pendingMode,
        captionScale,
        captionForeground,
        captionBackground,
        const MapEquality<HapticEvent, bool>().hash(hapticEnabled),
        strobeEnabled,
        language,
        audibleNoticeEnabled,
      );

  ThresholdSettings copyWith({
    CaptionMode? activeMode,
    CaptionMode? pendingMode,
    double? captionScale,
    Color? captionForeground,
    Color? captionBackground,
    Map<HapticEvent, bool>? hapticEnabled,
    bool? strobeEnabled,
    String? language,
    bool? audibleNoticeEnabled,
  }) {
    return ThresholdSettings(
      activeMode: activeMode ?? this.activeMode,
      pendingMode: pendingMode ?? this.pendingMode,
      captionScale: captionScale ?? this.captionScale,
      captionForeground: captionForeground ?? this.captionForeground,
      captionBackground: captionBackground ?? this.captionBackground,
      hapticEnabled: hapticEnabled ?? this.hapticEnabled,
      strobeEnabled: strobeEnabled ?? this.strobeEnabled,
      language: language ?? this.language,
      audibleNoticeEnabled: audibleNoticeEnabled ?? this.audibleNoticeEnabled,
    );
  }

  /// Sensible, accessible defaults: Clarity Mode, default scale, white on near
  /// black (high contrast), all haptics on, strobe off (FR-9.4), en-US.
  factory ThresholdSettings.defaults() => ThresholdSettings(
        activeMode: CaptionMode.clarity,
        pendingMode: CaptionMode.clarity,
        captionScale: 1.0,
        captionForeground: const Color(0xFFFFFFFF),
        captionBackground: const Color(0xFF000000),
        hapticEnabled: const <HapticEvent, bool>{
          HapticEvent.personAtDoor: true,
          HapticEvent.motion: true,
          HapticEvent.conversationStarted: true,
        },
        strobeEnabled: false,
        language: kFallbackLanguage,
        audibleNoticeEnabled: false,
      );
}
