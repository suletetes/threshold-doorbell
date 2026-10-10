// Persisted settings store (HIGH-10). The resident's accessibility settings
// (caption mode, size, colors, haptics, strobe, language, audible notice) MUST
// survive a relaunch (FR-10.x, NFR-2): losing them on every launch resets the
// accessibility configuration a Deaf or hard-of-hearing resident depends on.
//
// This defines the store interface, a shared_preferences-backed implementation,
// and an in-memory fake for tests. The settings value type is serialized to and
// from a small set of primitive keys so a stored blob is forward tolerant: a
// missing key falls back to the default for that field.

import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../alerts/haptic_vocabulary.dart';
import '../captions/language_selection.dart';
import 'settings_state.dart';

/// Loads and saves the resident's [ThresholdSettings] (HIGH-10). The live
/// binding wraps shared_preferences; the fake keeps a value in memory.
abstract class SettingsStore {
  /// Load persisted settings, or null when nothing has been saved yet (so the
  /// caller can use [ThresholdSettings.defaults]).
  Future<ThresholdSettings?> load();

  /// Persist [settings] so they survive a relaunch.
  Future<void> save(ThresholdSettings settings);

  /// Clear persisted settings (used by "Delete all my data", FR-8.6).
  Future<void> clear();
}

/// The shared_preferences keys. Namespaced so they cannot collide with other
/// stored values.
class _Keys {
  static const String prefix = 'threshold.settings.';
  static const String activeMode = '${prefix}activeMode';
  static const String pendingMode = '${prefix}pendingMode';
  static const String captionScale = '${prefix}captionScale';
  static const String captionForeground = '${prefix}captionForeground';
  static const String captionBackground = '${prefix}captionBackground';
  static const String strobeEnabled = '${prefix}strobeEnabled';
  static const String language = '${prefix}language';
  static const String audibleNoticeEnabled = '${prefix}audibleNoticeEnabled';
  static String haptic(HapticEvent e) => '${prefix}haptic.${e.name}';
}

String _modeToString(CaptionMode m) => m.name;

CaptionMode _modeFromString(String? s, CaptionMode fallback) {
  for (final m in CaptionMode.values) {
    if (m.name == s) return m;
  }
  return fallback;
}

/// Serialize settings to a flat map of primitives, and back. Exposed so both
/// the shared_preferences store and the in-memory fake share one encoding and a
/// test can assert the round-trip without a platform channel.
Map<String, Object> settingsToMap(ThresholdSettings s) {
  final map = <String, Object>{
    _Keys.activeMode: _modeToString(s.activeMode),
    _Keys.pendingMode: _modeToString(s.pendingMode),
    _Keys.captionScale: s.captionScale,
    // Store the full 32-bit ARGB value so alpha round-trips.
    _Keys.captionForeground: s.captionForeground.toARGB32(),
    _Keys.captionBackground: s.captionBackground.toARGB32(),
    _Keys.strobeEnabled: s.strobeEnabled,
    _Keys.language: s.language,
    _Keys.audibleNoticeEnabled: s.audibleNoticeEnabled,
  };
  for (final entry in s.hapticEnabled.entries) {
    map[_Keys.haptic(entry.key)] = entry.value;
  }
  return map;
}

/// Rebuild settings from a lookup function over the flat keys. A missing key
/// falls back to the corresponding default so an older or partial blob still
/// loads (forward tolerant).
ThresholdSettings settingsFromLookup(Object? Function(String key) get) {
  final defaults = ThresholdSettings.defaults();
  double scale(Object? v) => v is num ? v.toDouble() : defaults.captionScale;
  Color color(Object? v, Color fallback) => v is int ? Color(v) : fallback;
  bool flag(Object? v, bool fallback) => v is bool ? v : fallback;

  final haptics = <HapticEvent, bool>{};
  for (final event in HapticEvent.values) {
    final stored = get(_Keys.haptic(event));
    haptics[event] = flag(stored, defaults.hapticEnabled[event] ?? true);
  }

  return ThresholdSettings(
    activeMode:
        _modeFromString(get(_Keys.activeMode) as String?, defaults.activeMode),
    pendingMode: _modeFromString(
        get(_Keys.pendingMode) as String?, defaults.pendingMode),
    captionScale: scale(get(_Keys.captionScale)),
    captionForeground:
        color(get(_Keys.captionForeground), defaults.captionForeground),
    captionBackground:
        color(get(_Keys.captionBackground), defaults.captionBackground),
    hapticEnabled: haptics,
    strobeEnabled: flag(get(_Keys.strobeEnabled), defaults.strobeEnabled),
    language: (get(_Keys.language) as String?) ?? defaults.language,
    audibleNoticeEnabled:
        flag(get(_Keys.audibleNoticeEnabled), defaults.audibleNoticeEnabled),
  );
}

/// shared_preferences-backed [SettingsStore] (HIGH-10). Loaded before the first
/// frame in the composition root so the first frame already reflects the
/// resident's saved configuration.
class SharedPreferencesSettingsStore implements SettingsStore {
  SharedPreferencesSettingsStore(this._prefs);

  final SharedPreferences _prefs;

  /// Open the platform store. Call once at startup.
  static Future<SharedPreferencesSettingsStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    return SharedPreferencesSettingsStore(prefs);
  }

  @override
  Future<ThresholdSettings?> load() async {
    // Nothing saved yet: let the caller use the accessible defaults.
    if (!_prefs.containsKey(_Keys.activeMode)) return null;
    return settingsFromLookup((key) => _prefs.get(key));
  }

  @override
  Future<void> save(ThresholdSettings settings) async {
    final map = settingsToMap(settings);
    for (final entry in map.entries) {
      final value = entry.value;
      if (value is String) {
        await _prefs.setString(entry.key, value);
      } else if (value is int) {
        await _prefs.setInt(entry.key, value);
      } else if (value is double) {
        await _prefs.setDouble(entry.key, value);
      } else if (value is bool) {
        await _prefs.setBool(entry.key, value);
      }
    }
  }

  @override
  Future<void> clear() async {
    final keys =
        _prefs.getKeys().where((k) => k.startsWith(_Keys.prefix)).toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }
}

/// In-memory [SettingsStore] for tests and local runs. Holds the last saved
/// value so a test can prove settings survive a simulated relaunch (construct a
/// fresh controller from the same store).
class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([ThresholdSettings? initial]) : _saved = initial;

  ThresholdSettings? _saved;

  @override
  Future<ThresholdSettings?> load() async => _saved;

  @override
  Future<void> save(ThresholdSettings settings) async => _saved = settings;

  @override
  Future<void> clear() async => _saved = null;
}
