// Settings controller (Task 24, FR-8.6, FR-10.1..FR-10.4, NFR-2; AT-9). Owns the
// ThresholdSettings, applies the mode switch to the NEXT session (FR-10.1),
// enforces the caption contrast floor on every change (FR-10.2, NFR-2), toggles
// haptics and the off-by-default strobe (FR-9.4, FR-10.3), and runs the
// confirmed "Delete all my data" erasure (FR-8.6) behind a port. A
// ChangeNotifier so the Settings screen rebuilds.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../alerts/haptic_vocabulary.dart';
import '../captions/language_selection.dart';
import 'settings_state.dart';
import 'settings_store.dart';

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

/// The state of the "Delete all my data" request (FR-8.6, HIGH-08). Drives the
/// settings screen's success/failure banner and the in-flight button disable.
enum ErasureStatus { idle, inFlight, success, failure }

class SettingsController extends ChangeNotifier {
  SettingsController({
    required DataErasurePort erasure,
    ThresholdSettings? initial,
    SettingsStore? store,
  })  : _erasure = erasure,
        _store = store,
        _settings = initial ?? ThresholdSettings.defaults();

  final DataErasurePort _erasure;

  /// Persists settings across relaunches (HIGH-10). Optional so a test can
  /// construct a controller with no persistence; the composition root always
  /// supplies a shared_preferences-backed store.
  final SettingsStore? _store;
  ThresholdSettings _settings;

  ThresholdSettings get settings => _settings;

  /// Build a controller from a persisted store (HIGH-10). Loads the saved
  /// settings before the controller is first read so the first frame already
  /// reflects the resident's configuration; falls back to accessible defaults
  /// when nothing has been saved yet.
  static Future<SettingsController> load({
    required DataErasurePort erasure,
    required SettingsStore store,
  }) async {
    final saved = await store.load();
    return SettingsController(
      erasure: erasure,
      initial: saved ?? ThresholdSettings.defaults(),
      store: store,
    );
  }

  /// The current erasure request status (HIGH-08). The screen renders a banner
  /// from this and disables the delete button while [ErasureStatus.inFlight].
  ErasureStatus _erasureStatus = ErasureStatus.idle;
  ErasureStatus get erasureStatus => _erasureStatus;
  bool get erasureInFlight => _erasureStatus == ErasureStatus.inFlight;

  void _update(ThresholdSettings next) {
    if (next == _settings) return; // value equality (LOW-06): skip no-op writes
    _settings = next;
    // Persist so the change survives a relaunch (HIGH-10). Fire and forget: a
    // failed write must not block the UI, and the in-memory value is already
    // updated. A thrown store error is swallowed rather than escaping a setter.
    unawaited(_persist(next));
    notifyListeners();
  }

  Future<void> _persist(ThresholdSettings settings) async {
    final store = _store;
    if (store == null) return;
    try {
      await store.save(settings);
    } catch (_) {
      // Persistence is best effort; never surface a store failure to the UI.
    }
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

  /// Optional hook fired whenever the person-at-door haptic toggle changes
  /// (FR-9.2). The composition root sets this to mirror the setting into the
  /// doorbell alert service, so a disabled haptic means a silent (visual only)
  /// ring. Kept as a callback so this controller stays free of any platform
  /// plugin and remains unit-testable.
  void Function(bool enabled)? onPersonAtDoorHapticChanged;

  /// Enable or disable a single haptic pattern (FR-10.3).
  void setHapticEnabled(HapticEvent event, bool enabled) {
    final next = Map<HapticEvent, bool>.from(_settings.hapticEnabled);
    next[event] = enabled;
    _update(_settings.copyWith(hapticEnabled: next));
    if (event == HapticEvent.personAtDoor) {
      onPersonAtDoorHapticChanged?.call(enabled);
    }
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

  /// Run the confirmed "Delete all my data" erasure (FR-8.6, HIGH-08). The
  /// caller shows the confirmation; this performs the erasure only when
  /// [confirmed] is true. The result is captured in [erasureStatus] so the
  /// screen can show a success or failure banner and disable the button while
  /// in flight; on success local settings are reset so no local data survives
  /// an erasure the resident asked for. The error is never swallowed: a thrown
  /// binding resolves to [ErasureStatus.failure] rather than an unhandled
  /// exception out of a button callback.
  Future<bool> deleteAllMyData({required bool confirmed}) async {
    if (!confirmed) return false;
    _erasureStatus = ErasureStatus.inFlight;
    notifyListeners();
    bool ok;
    try {
      ok = await _erasure.deleteAllMyData();
    } catch (_) {
      ok = false;
    }
    if (ok) {
      // Clear local state so an erasure leaves nothing behind on the device,
      // including the persisted copy (HIGH-10): the reset must survive a
      // relaunch too, not resurrect the old settings from the store.
      _settings = ThresholdSettings.defaults();
      unawaited(_persistClearThenDefaults());
      _erasureStatus = ErasureStatus.success;
    } else {
      _erasureStatus = ErasureStatus.failure;
    }
    notifyListeners();
    return ok;
  }

  /// After an erasure, clear the persisted store so the defaults survive a
  /// relaunch (HIGH-10): the resident asked for everything to be removed.
  Future<void> _persistClearThenDefaults() async {
    final store = _store;
    if (store == null) return;
    try {
      await store.clear();
    } catch (_) {
      // Best effort: a failed clear must not surface out of the erasure flow.
    }
  }

  /// Dismiss the erasure banner (HIGH-08), returning to the idle state.
  void dismissErasureStatus() {
    if (_erasureStatus == ErasureStatus.idle) return;
    _erasureStatus = ErasureStatus.idle;
    notifyListeners();
  }
}
