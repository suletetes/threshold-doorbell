import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ring_captions/flutter_ring_captions.dart';

void main() {
  group('stripDashes', () {
    test('replaces an em-dash with a spaced hyphen', () {
      expect(stripDashes('one\u2014two'), 'one - two');
    });

    test('replaces an en-dash', () {
      expect(stripDashes('a\u2013b'), 'a - b');
    });

    test('leaves clean text unchanged', () {
      expect(stripDashes('please leave it at the door'), 'please leave it at the door');
    });

    test('collapses whitespace introduced by replacement', () {
      expect(stripDashes('a \u2014 b'), 'a - b');
    });
  });

  group('sanitizeSuggestions', () {
    test('drops non-strings, empties, and dedupes, capping at 3', () {
      final out = sanitizeSuggestions(<Object?>['ok', 42, '', 'ok', 'sure', 'later', 'extra']);
      expect(out, ['ok', 'sure', 'later']);
    });

    test('strips dashes from suggestions', () {
      final out = sanitizeSuggestions(<Object?>['hold on\u2014one sec']);
      expect(out.single.contains('\u2014'), isFalse);
    });
  });

  group('replyBarSuggestions', () {
    test('is never empty, backed by the fixed safe set', () {
      expect(replyBarSuggestions(<Object?>[]), kFixedSafeReplies);
    });

    test('model replies come first, then safe set fills up to 3', () {
      final out = replyBarSuggestions(<Object?>['On my way']);
      expect(out.first, 'On my way');
      expect(out.length, 3);
    });

    test('never exceeds 3 even with many model replies', () {
      final out = replyBarSuggestions(<Object?>['a', 'b', 'c', 'd', 'e']);
      expect(out.length, 3);
    });

    test('no forbidden dash ever appears in the final bar', () {
      final out = replyBarSuggestions(<Object?>['hold\u2014on', 'wait\u2013here']);
      for (final s in out) {
        expect(s.contains('\u2014'), isFalse);
        expect(s.contains('\u2013'), isFalse);
      }
    });
  });
}
