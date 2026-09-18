import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/captions/language_selection.dart';

void main() {
  const supported = SupportedLanguages.defaults;

  group('normalizeLanguageTag (Task 23, FR-16.1)', () {
    test('canonicalizes underscores and case to ll-RR', () {
      expect(normalizeLanguageTag('en_us'), 'en-US');
      expect(normalizeLanguageTag('ES-es'), 'es-ES');
      expect(normalizeLanguageTag('  fr-fr '), 'fr-FR');
    });

    test('leaves a bare language as lowercase', () {
      expect(normalizeLanguageTag('EN'), 'en');
    });

    test('empty stays empty', () {
      expect(normalizeLanguageTag(''), '');
    });
  });

  group('defaultLanguageFor (Task 23, FR-16.1) [R-13]', () {
    test('uses the device locale when supported in the mode', () {
      final locale = FixtureLocaleSource('fr-FR');
      expect(defaultLanguageFor(CaptionMode.clarity, locale, supported), 'fr-FR');
    });

    test('normalizes the device locale before matching', () {
      final locale = FixtureLocaleSource('es_us');
      expect(defaultLanguageFor(CaptionMode.clarity, locale, supported), 'es-US');
    });

    test('falls back to en-US when the device locale is unsupported (FR-16.1)', () {
      final locale = FixtureLocaleSource('sv-SE'); // not in either set
      expect(defaultLanguageFor(CaptionMode.clarity, locale, supported), 'en-US');
      expect(defaultLanguageFor(CaptionMode.privacy, locale, supported), 'en-US');
    });

    test('privacy mode has a narrower set: a Clarity-only locale falls back', () {
      final locale = FixtureLocaleSource('de-DE'); // clarity yes, privacy no
      expect(defaultLanguageFor(CaptionMode.clarity, locale, supported), 'de-DE');
      expect(defaultLanguageFor(CaptionMode.privacy, locale, supported), 'en-US');
    });

    test('last-resort picks the first supported language when en-US absent (custom set)', () {
      const custom = SupportedLanguages(clarity: <String>{'ja-JP', 'ko-KR'}, privacy: <String>{'ja-JP'});
      final locale = FixtureLocaleSource('sv-SE');
      expect(defaultLanguageFor(CaptionMode.clarity, locale, custom), 'ja-JP');
    });
  });

  group('validateSelection (Task 23, FR-16.2, 16.3; AT-22)', () {
    test('a supported selection is accepted with no alternative', () {
      final locale = FixtureLocaleSource('en-US');
      final sel = validateSelection('es-ES', CaptionMode.clarity, locale, supported);
      expect(sel.supported, isTrue);
      expect(sel.language, 'es-ES');
      expect(sel.alternative, isNull);
    });

    test('an unsupported selection is reported before the session with an alternative (FR-16.3, AT-22)', () {
      final locale = FixtureLocaleSource('en-GB');
      final sel = validateSelection('sv-SE', CaptionMode.clarity, locale, supported);
      expect(sel.supported, isFalse);
      // The alternative is the mode default: the device locale (en-GB, supported in clarity).
      expect(sel.alternative, 'en-GB');
    });

    test('unsupported in privacy offers the privacy default (device locale not in privacy -> en-US)', () {
      final locale = FixtureLocaleSource('de-DE');
      // de-DE is unsupported in privacy; the device locale is also unsupported in
      // privacy, so the offered alternative is en-US.
      final sel = validateSelection('de-DE', CaptionMode.privacy, locale, supported);
      expect(sel.supported, isFalse);
      expect(sel.alternative, 'en-US');
    });

    test('a language supported in clarity but not privacy is flagged per mode (FR-16.2)', () {
      final locale = FixtureLocaleSource('en-US');
      expect(validateSelection('ja-JP', CaptionMode.clarity, locale, supported).supported, isTrue);
      expect(validateSelection('ja-JP', CaptionMode.privacy, locale, supported).supported, isFalse);
    });

    test('normalizes the requested tag before validating', () {
      final locale = FixtureLocaleSource('en-US');
      final sel = validateSelection('FR_fr', CaptionMode.clarity, locale, supported);
      expect(sel.supported, isTrue);
      expect(sel.language, 'fr-FR');
    });

    test('isSupported respects the per-mode set', () {
      expect(supported.isSupported('pt-BR', CaptionMode.clarity), isTrue);
      expect(supported.isSupported('pt-BR', CaptionMode.privacy), isFalse);
    });
  });
}
