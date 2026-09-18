import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/captions/turn_segmentation.dart';

CaptionResult r(
  CaptionSpeaker speaker,
  String text,
  int ts, {
  bool isFinal = false,
  bool boundary = false,
  double? confidence,
}) {
  return CaptionResult(
    speaker: speaker,
    text: text,
    isFinal: isFinal,
    timestampMs: ts,
    segmentBoundary: boundary,
    confidence: confidence,
  );
}

void main() {
  group('startsNewTurn (FR-5.5)', () {
    test('a first result always starts a turn', () {
      expect(startsNewTurn(null, r(CaptionSpeaker.visitor, 'hi', 0)), isTrue);
    });

    test('a speaker change starts a new turn', () {
      final acc = TurnAccumulator()..apply(r(CaptionSpeaker.visitor, 'hi', 0));
      expect(startsNewTurn(acc.current, r(CaptionSpeaker.resident, 'reply', 100)), isTrue);
    });

    test('a finalized current turn forces a new turn', () {
      final acc = TurnAccumulator()..apply(r(CaptionSpeaker.visitor, 'done', 0, isFinal: true, confidence: 0.9));
      expect(startsNewTurn(acc.current, r(CaptionSpeaker.visitor, 'again', 100)), isTrue);
    });

    test('an engine segment boundary starts a new turn', () {
      final acc = TurnAccumulator()..apply(r(CaptionSpeaker.visitor, 'first', 0));
      expect(startsNewTurn(acc.current, r(CaptionSpeaker.visitor, 'second', 100, boundary: true)), isTrue);
    });

    test('a long pause starts a new turn even for the same speaker', () {
      final acc = TurnAccumulator()..apply(r(CaptionSpeaker.visitor, 'first', 0));
      expect(
        startsNewTurn(acc.current, r(CaptionSpeaker.visitor, 'later', kTurnPauseThresholdMs + 1)),
        isTrue,
      );
    });

    test('a quick continuation of the same speaker extends the turn', () {
      final acc = TurnAccumulator()..apply(r(CaptionSpeaker.visitor, 'hel', 0));
      expect(startsNewTurn(acc.current, r(CaptionSpeaker.visitor, 'hello', 200)), isFalse);
    });
  });

  group('TurnAccumulator (FR-5.5, FR-5.7)', () {
    test('extends a partial without concatenating across boundaries', () {
      final acc = TurnAccumulator()
        ..apply(r(CaptionSpeaker.visitor, 'hel', 0))
        ..apply(r(CaptionSpeaker.visitor, 'hello', 200))
        ..apply(r(CaptionSpeaker.visitor, 'hello there', 400, isFinal: true, confidence: 0.9));
      expect(acc.turns, hasLength(1));
      expect(acc.turns.single.text, 'hello there');
      expect(acc.turns.single.isFinal, isTrue);
      expect(acc.turns.single.provisional, isFalse);
      expect(acc.turns.single.confidence, 0.9);
    });

    test('produces separate labeled turns on speaker change', () {
      final acc = TurnAccumulator()
        ..apply(r(CaptionSpeaker.visitor, 'is anyone home', 0, isFinal: true, confidence: 0.8))
        ..apply(r(CaptionSpeaker.resident, 'Please leave it at the door', 500, isFinal: true, confidence: 0.95));
      expect(acc.turns, hasLength(2));
      expect(acc.turns[0].speaker, CaptionSpeaker.visitor);
      expect(acc.turns[1].speaker, CaptionSpeaker.resident);
    });

    test('a partial turn keeps null confidence while provisional (FR-5.7)', () {
      final acc = TurnAccumulator()..apply(r(CaptionSpeaker.visitor, 'partial...', 0));
      expect(acc.turns.single.provisional, isTrue);
      expect(acc.turns.single.confidence, isNull);
    });

    test('finalizeForPersistence keeps a trailing partial as provisional null (FR-5.7)', () {
      final acc = TurnAccumulator()
        ..apply(r(CaptionSpeaker.visitor, 'done', 0, isFinal: true, confidence: 0.9))
        ..apply(r(CaptionSpeaker.visitor, 'unfinished', kTurnPauseThresholdMs + 10));
      final persisted = acc.finalizeForPersistence();
      expect(persisted, hasLength(2));
      expect(persisted.last.text, 'unfinished');
      expect(persisted.last.provisional, isTrue);
      expect(persisted.last.confidence, isNull);
      expect(persisted.last.isFinal, isFalse);
    });

    test('a pause boundary splits same-speaker turns', () {
      final acc = TurnAccumulator()
        ..apply(r(CaptionSpeaker.visitor, 'hello', 0, isFinal: true, confidence: 0.9))
        ..apply(r(CaptionSpeaker.visitor, 'are you there', kTurnPauseThresholdMs + 100, isFinal: true, confidence: 0.9));
      expect(acc.turns, hasLength(2));
    });
  });
}
