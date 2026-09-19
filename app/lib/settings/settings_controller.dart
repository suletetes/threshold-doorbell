// Settings controller (Task 24, FR-8.6, FR-10.1..FR-10.4, NFR-2; AT-9). Owns the
// ThresholdSettings, applies the mode switch to the NEXT session (FR-10.1),
// enforces the caption contrast floor on every change (FR-10.2, NFR-2), toggles
// haptics and the off-by-default strobe (FR-9.4, FR-10.3), and runs the
// confirmed "Delete all my data" erasure (FR-8.6) behind a port. A
// ChangeNotifier so the Settings screen rebuilds.

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../alerts/haptic_vocabulary.dart';
import '../captions/language_selection.dart';
import 'settings_state.dart';

/// Erasure port for "Delete all my data" (FR-8.6): erases all transcripts and
/// revokes stored Ring tokens on the backend. Network-bound, behind a fake.
abstract class DataErasurePort {
  /// Erase everything for the resident (transcripts + tokens). Returns true on
  /// success. Called only after an explicit confirmation (FR-8.6).
  Future<bool> deleteAllMyData();
}

/// Deterministic fake for tests.
class FakeDataErasurePort implements DataErasurePort {
  FakeDataErasurePort({this.succeeds = true});
  final bool succeeds;
  int deleteCalls = 0;

  @override
  Future<bool> deleteAllMyData() async {
    deleteCalls++;
    return succeeds;
  }
}

class SettingsController extends ChangeNotifier {
  SettingsController({
    required DataErasurePort erasure,
    ThresholdSettings? initial,
  })  : _erasure = erasure,
        _settings = initial ?? ThresholdSettings.defaults();

  final DataErasurePort _erasure;
  ThresholdSettings _settings;

  ThresholdSettings get settings => _settings;

  void _update(ThresholdSettings next) {
    _settings = next;
    notifyListeners();
  }

  /// Switch caption mode. The change applies to the NEXT session (FR-10.1); the
  /// active session keeps running its current mode. Stored as [pendingMode].
  void requestModeChange(CaptionMode mode) {
    _update(_settings.copyWith(pendingMode: mode));
  }

  /// Promote the pending mode to active at the start of a new session (FR-10.1).
  void applyPendingModeForNewSession() {
    _update(_settings.copyWith(activeMode: _settings.pendingMode));
  }

  /// Set the caption text scale; clamped to [1.0, 2.0] by the model (FR-10.2).
  void setCaptionScale(double scale) {
    _update(_settings.copyWith(captionScale: scale));
  }

  /// Set caption colors; the model enforces the 4.5:1 floor so the resident can
  /// never breach NFR-2 (FR-10.2).
  void setCaptionColors({Color? foreground, Color? background}) {
    _update(_settings.copyWith(
      captionForeground: foreground,
      captionBackground: background,
    ));
  }

  /// Enable or disable a single haptic pattern (FR-10.3).
  void setHapticEnabled(HapticEvent event, bool enabled) {
    final next = Map<HapticEvent, bool>.from(_settings.hapticEnabled);
    next[event] = enabled;
    _update(_settings.copyWith(hapticEnabled: next));
  }

  /// Toggle the screen strobe / torch (off by default, FR-9.4).
  void setStrobeEnabled(bool enabled) {
    _update(_settings.copyWith(strobeEnabled: enabled));
  }

  /// Set the recognition language (FR-16).
  void setLanguage(String language) {
    _update(_settings.copyWith(language: language));
  }

  /// Toggle the optional audible door notice (FR-14.3).
  void setAudibleNoticeEnabled(bool enabled) {
    _update(_settings.copyWith(audibleNoticeEnabled: enabled));
  }

  /// Run the confirmed "Delete all my data" erasure (FR-8.6). The caller shows
  /// the confirmation; this performs the erasure only when [confirmed] is true.
  Future<bool> deleteAllMyData({required bool confirmed}) async {
    if (!confirmed) return false;
    return _erasure.deleteAllMyData();
  }
}
