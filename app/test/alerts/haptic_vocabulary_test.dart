import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/alerts/haptic_vocabulary.dart';

void main() {
  group('HapticVocabulary (FR-9.1, FR-9.2)', () {
    test('defines exactly three patterns in v1', () {
      expect(HapticVocabulary.all.length, 3);
    });

    test('the three patterns cover the three events, one each', () {
      final events = HapticVocabulary.all.map((p) => p.event).toSet();
      expect(events, {
        HapticEvent.personAtDoor,
        HapticEvent.motion,
        HapticEvent.conversationStarted,
      });
    });

    test('patterns are distinguishable (distinct timing signatures)', () {
      final signatures =
          HapticVocabulary.all.map((p) => p.timings.join(',')).toSet();
      // Three distinct signatures => three distinguishable patterns.
      expect(signatures.length, 3);
    });

    test('forEvent is total over the enum', () {
      for (final event in HapticEvent.values) {
        final pattern = HapticVocabulary.forEvent(event);
        expect(pattern.event, event);
        expect(pattern.timings.length, greaterThan(1));
      }
    });

    test('every timing list starts with a wait and has an even length', () {
      for (final p in HapticVocabulary.all) {
        expect(p.timings.first, 0, reason: 'first entry is the initial wait');
        expect(p.timings.length.isEven, isTrue);
        expect(p.totalDurationMs, greaterThan(0));
      }
    });

    test('labels contain no em-dash or en-dash (NFR-10)', () {
      for (final p in HapticVocabulary.all) {
        expect(p.label.contains('\u2014'), isFalse);
        expect(p.label.contains('\u2013'), isFalse);
      }
    });

    test('fromEventType maps known types and returns null for drift', () {
      expect(HapticVocabulary.fromEventType('person_detected'),
          HapticEvent.personAtDoor);
      expect(HapticVocabulary.fromEventType('motion_detected'),
          HapticEvent.motion);
      expect(
        HapticVocabulary.fromEventType('conversation_started'),
        HapticEvent.conversationStarted,
      );
      expect(HapticVocabulary.fromEventType('unknown_event'), isNull);
    });
  });
}
