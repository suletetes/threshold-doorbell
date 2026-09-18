// Recognition-language selection (Task 23, FR-16.1..16.3; AT-22). Pure logic for
// choosing the caption recognition language and validating it against the
// supported set for the active caption mode. Clarity Mode (Amazon Transcribe)
// and Privacy Mode (on-device Whisper) may support different language sets
// (FR-16.2), so support is modeled per mode. The device locale source is behind
// LocaleSource (fixture below) so the default-and-fallback rule is testable
// without a device.

import 'package:flutter/foundation.dart';

/// The caption mode a language set belongs to. Mirrors design.md §3 CaptionMode.
enum CaptionMode { clarity, privacy }

/// The universal fallback recognition language when the device locale is not
/// supported in the active mode (FR-16.1) [R-13].
const String kFallbackLanguage = 'en-US';

/// Normalize a raw locale/BCP-47 tag to the canonical `ll-RR` form used by the
/// supported sets. Accepts underscores, mixed case, and a bare language. A bare
/// language (for example `en`) is left as-is so it can match a set entry that
/// is itself a bare language; region case is upper, language case is lower.
String normalizeLanguageTag(String raw) {
  final trimmed = raw.trim().replaceAll('_', '-');
  if (trimmed.isEmpty) return trimmed;
  final parts = trimmed.split('-');
  final lang = parts.first.toLowerCase();
  if (parts.length == 1) return lang;
  final region = parts[1].toUpperCase();
  return '$lang-$region';
}

/// The supported recognition languages per mode (FR-16.2). These are the
/// documented sets; a real build sources them from the engines. Clarity Mode
/// (cloud Transcribe) supports a broader set than Privacy Mode (on-device),
/// which is deliberately narrower to reflect the on-device model.
class SupportedLanguages {
  const SupportedLanguages({required this.clarity, required this.privacy});

  final Set<String> clarity;
  final Set<String> privacy;

  /// The default documented sets. Values are already normalized `ll-RR`.
  static const SupportedLanguages defaults = SupportedLanguages(
    clarity: <String>{
      'en-US',
      'en-GB',
      'es-US',
      'es-ES',
      'fr-FR',
      'de-DE',
      'pt-BR',
      'it-IT',
      'ja-JP',
    },
    privacy: <String>{
      'en-US',
      'es-US',
      'fr-FR',
    },
  );

  Set<String> forMode(CaptionMode mode) =>
      mode == CaptionMode.clarity ? clarity : privacy;

  bool isSupported(String language, CaptionMode mode) =>
      forMode(mode).contains(normalizeLanguageTag(language));
}

/// Source of the device locale. The live binding reads the platform locale
/// (deferred to device); the fixture supplies a fixed tag for tests.
abstract class LocaleSource {
  /// The device locale as a BCP-47 tag (for example `en-US`).
  String get deviceLocale;
}

/// Deterministic fixture locale source.
class FixtureLocaleSource implements LocaleSource {
  FixtureLocaleSource(this._locale);
  final String _locale;
  @override
  String get deviceLocale => _locale;
}

/// The outcome of validating a requested language against a mode (FR-16.3).
@immutable
class LanguageSelection {
  const LanguageSelection({
    required this.language,
    required this.supported,
    this.alternative,
  });

  /// The requested (normalized) language.
  final String language;

  /// Whether it is supported in the active mode.
  final bool supported;

  /// A supported alternative to offer when [supported] is false (FR-16.3).
  /// null only when the mode has no supported languages at all (never in
  /// practice, since en-US is always present).
  final String? alternative;
}

/// Choose the default recognition language for a mode (FR-16.1): the device
/// locale when supported, otherwise `en-US` [R-13]. If neither the device
/// locale nor en-US is supported in the mode (only possible with a custom set),
/// the first supported language is used so the caller always gets a usable value.
String defaultLanguageFor(CaptionMode mode, LocaleSource locale, SupportedLanguages supported) {
  final device = normalizeLanguageTag(locale.deviceLocale);
  final set = supported.forMode(mode);
  if (set.contains(device)) return device;
  if (set.contains(kFallbackLanguage)) return kFallbackLanguage;
  // Deterministic last resort: the lexicographically first supported language.
  final sorted = set.toList()..sort();
  return sorted.isNotEmpty ? sorted.first : kFallbackLanguage;
}

/// Validate a user-selected language for a mode before a session starts
/// (FR-16.3). When unsupported, offers a supported alternative: the mode's
/// default language (device locale or en-US).
LanguageSelection validateSelection(
  String requested,
  CaptionMode mode,
  LocaleSource locale,
  SupportedLanguages supported,
) {
  final normalized = normalizeLanguageTag(requested);
  final isSupported = supported.isSupported(normalized, mode);
  if (isSupported) {
    return LanguageSelection(language: normalized, supported: true);
  }
  // Offer the mode default as the alternative (FR-16.3).
  final alt = defaultLanguageFor(mode, locale, supported);
  return LanguageSelection(language: normalized, supported: false, alternative: alt);
}
