import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/reply/ondevice_suggestions.dart';

void main() {
  group('onDeviceSuggestions (Task 18, FR-7.1a, 7.2, 7.5; AT-8, AT-21)', () {
    test('offers a keyword template first when a trigger matches', () {
      final s = onDeviceSuggestions('I have a package for you');
      expect(s.first, 'Please leave it at the door');
      expect(s.length, lessThanOrEqualTo(3));
    });

    test('never empty even with no matches (fixed safe set fills, FR-7.5)', () {
      final s = onDeviceSuggestions('mumble mumble');
      expect(s, isNotEmpty);
      expect(s.length, lessThanOrEqualTo(3));
      // The fixed safe set is present as the fallback.
      expect(s.first, kFixedSafeReplies.first);
    });

    test('never exceeds 3 suggestions (FR-7.1)', () {
      final s = onDeviceSuggestions('package delivery who name help later');
      expect(s.length, 3);
    });

    test('deduplicates so a template that equals a safe reply appears once', () {
      final s = onDeviceSuggestions('sign for the parcel');
      final counts = <String, int>{};
      for (final x in s) {
        counts[x] = (counts[x] ?? 0) + 1;
      }
      expect(counts.values.every((c) => c == 1), isTrue);
    });

    test('matching is case-insensitive', () {
      final s = onDeviceSuggestions('PACKAGE');
      expect(s.first, 'Please leave it at the door');
    });

    test('always includes at least one fixed safe reply', () {
      final s = onDeviceSuggestions('who is at the door');
      final hasSafe = s.any(kFixedSafeReplies.contains);
      expect(hasSafe, isTrue);
    });

    test('matches on word boundaries, not substrings (LOW-03)', () {
      // "whole" must NOT trigger the "who" template, and "design" must NOT
      // trigger the "sign" template. The old substring match offered them.
      final whole = onDeviceSuggestions('the whole street is busy');
      expect(whole.contains('Who is this please'), isFalse);
      final design = onDeviceSuggestions('I like your design');
      expect(design.contains('Please leave it at the door'),
          isTrue); // only from the safe-set fill, not the sign template
      // The whole-word "who" still matches.
      final who = onDeviceSuggestions('who is this');
      expect(who.contains('Who is this please'), isTrue);
    });

    test('no suggestion contains a forbidden dash (NFR-10)', () {
      final all = <String>[
        ...onDeviceSuggestions('package who help later'),
        ...kFixedSafeReplies,
      ];
      for (final s in all) {
        expect(s.contains('\u2014'), isFalse);
        expect(s.contains('\u2013'), isFalse);
      }
    });
  });
}
