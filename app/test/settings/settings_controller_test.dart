import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/alerts/haptic_vocabulary.dart';
import 'package:threshold/captions/language_selection.dart';
import 'package:threshold/settings/contrast.dart';
import 'package:threshold/settings/settings_controller.dart';
import 'package:threshold/settings/settings_state.dart';

void main() {
  group('ThresholdSettings model (Task 24, FR-10.2, NFR-2; AT-9)', () {
    test('defaults: Clarity, scale 1.0, strobe off, all haptics on, en-US', () {
      final s = ThresholdSettings.defaults();
      expect(s.activeMode, CaptionMode.clarity);
      expect(s.captionScale, 1.0);
      expect(s.strobeEnabled, isFalse); // off by default (FR-9.4)
      expect(s.language, kFallbackLanguage);
      expect(s.hapticEnabled.values.every((v) => v), isTrue);
      expect(s.meetsContrastFloor, isTrue);
    });

    test('caption scale is clamped to [1.0, 2.0] (FR-10.2, NFR-2)', () {
      final tooBig = ThresholdSettings.defaults().copyWith(captionScale: 5.0);
      expect(tooBig.captionScale, kMaxCaptionScale);
      final tooSmall = ThresholdSettings.defaults().copyWith(captionScale: 0.1);
      expect(tooSmall.captionScale, kMinCaptionScale);
    });

    test('a low-contrast caption color is raised to meet the floor (FR-10.2)',
        () {
      final s = ThresholdSettings.defaults().copyWith(
        captionForeground: const Color(0xFFBBBBBB),
        captionBackground: const Color(0xFFFFFFFF),
      );
      expect(s.meetsContrastFloor, isTrue);
      expect(s.captionContrastRatio >= kContrastFloor - 1e-9, isTrue);
    });

    test('retention label shows 90 days and is dash-free (FR-8.5, NFR-10)', () {
      final s = ThresholdSettings.defaults();
      expect(s.retentionLabel.contains('90'), isTrue);
      expect(s.retentionLabel.contains('\u2014'), isFalse);
      expect(s.retentionLabel.contains('\u2013'), isFalse);
    });
  });

  group('SettingsController (Task 24, FR-8.6, FR-10.1, FR-10.3; AT-9)', () {
    test(
        'mode switch applies to the NEXT session, not the active one (FR-10.1)',
        () {
      final c = SettingsController(erasure: FakeDataErasurePort());
      c.requestModeChange(CaptionMode.privacy);
      expect(c.settings.activeMode, CaptionMode.clarity); // unchanged now
      expect(c.settings.pendingMode, CaptionMode.privacy);
      c.applyPendingModeForNewSession();
      expect(c.settings.activeMode, CaptionMode.privacy);
    });

    test('haptic toggles flip individually (FR-10.3)', () {
      final c = SettingsController(erasure: FakeDataErasurePort());
      c.setHapticEnabled(HapticEvent.motion, false);
      expect(c.settings.hapticEnabled[HapticEvent.motion], isFalse);
      expect(c.settings.hapticEnabled[HapticEvent.personAtDoor], isTrue);
    });

    test('strobe toggle flips (off by default, FR-9.4)', () {
      final c = SettingsController(erasure: FakeDataErasurePort());
      expect(c.settings.strobeEnabled, isFalse);
      c.setStrobeEnabled(true);
      expect(c.settings.strobeEnabled, isTrue);
    });

    test('setting a low-contrast color still enforces the floor (FR-10.2)', () {
      final c = SettingsController(erasure: FakeDataErasurePort());
      c.setCaptionColors(
        foreground: const Color(0xFFCCCCCC),
        background: const Color(0xFFFFFFFF),
      );
      expect(c.settings.meetsContrastFloor, isTrue);
    });

    test('delete all my data only runs when confirmed (FR-8.6)', () async {
      final port = FakeDataErasurePort();
      final c = SettingsController(erasure: port);
      final notConfirmed = await c.deleteAllMyData(confirmed: false);
      expect(notConfirmed, isFalse);
      expect(port.deleteCalls, 0);
      final confirmed = await c.deleteAllMyData(confirmed: true);
      expect(confirmed, isTrue);
      expect(port.deleteCalls, 1);
    });

    test(
        'a successful erasure records success and clears local settings (HIGH-08)',
        () async {
      final c =
          SettingsController(erasure: FakeDataErasurePort(succeeds: true));
      c.setCaptionScale(2.0); // dirty the local state
      expect(c.settings.captionScale, 2.0);
      await c.deleteAllMyData(confirmed: true);
      expect(c.erasureStatus, ErasureStatus.success);
      // Local state is reset so nothing survives the erasure.
      expect(
          c.settings.captionScale, ThresholdSettings.defaults().captionScale);
    });

    test(
        'a failed erasure records failure and does not reset local settings (HIGH-08)',
        () async {
      final c =
          SettingsController(erasure: FakeDataErasurePort(succeeds: false));
      c.setCaptionScale(2.0);
      await c.deleteAllMyData(confirmed: true);
      expect(c.erasureStatus, ErasureStatus.failure);
      expect(c.settings.captionScale, 2.0); // local state untouched on failure
    });

    test(
        'a throwing erasure resolves to failure, never an unhandled throw (HIGH-08)',
        () async {
      final c = SettingsController(erasure: _ThrowingErasurePort());
      final ok = await c.deleteAllMyData(confirmed: true);
      expect(ok, isFalse);
      expect(c.erasureStatus, ErasureStatus.failure);
    });

    test('dismissing the erasure banner returns to idle (HIGH-08)', () async {
      final c =
          SettingsController(erasure: FakeDataErasurePort(succeeds: true));
      await c.deleteAllMyData(confirmed: true);
      expect(c.erasureStatus, ErasureStatus.success);
      c.dismissErasureStatus();
      expect(c.erasureStatus, ErasureStatus.idle);
    });
  });
}

/// An erasure port that always throws, modelling the production binding with no
/// network (HIGH-08).
class _ThrowingErasurePort implements DataErasurePort {
  @override
  Future<bool> deleteAllMyData() async => throw StateError('no network');
}
