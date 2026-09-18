import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ring_captions/flutter_ring_captions.dart';

CaptionResult r(
  CaptionSpeaker speaker,
  String text, {
  bool isFinal = false,
  int t = 0,
  bool boundary = false,
  double? confidence,
}) =>
    CaptionResult(
      speaker: speaker,
      text: text,
      isFinal: isFinal,
      timestampMs: t,
      segmentBoundary: boundary,
      confidence: confidence,
    );

void main() {
  group('startsNewTurn', () {
    test('a first result always starts a turn', () {
      expect(startsNewTurn(null, r(CaptionSpeaker.visitor, 'hi')), isTrue);
    });

    test('a speaker change starts a new turn', () {
      final a = TurnAccumulator()..apply(r(CaptionSpeaker.visitor, 'hi'));
      expect(startsNewTurn(a.current, r(CaptionSpeaker.resident, 'hello')), isTrue);
    });

    test('an engine boundary starts a new turn', () {
      final a = TurnAccumulator()..apply(r(CaptionSpeaker.visitor, 'hi'));
      expect(startsNewTurn(a.current, r(CaptionSpeaker.visitor, 'again', boundary: true)), isTrue);
    });

    test('a long pause splits the same speaker', () {
      final a = TurnAccumulator()..apply(r(CaptionSpeaker.visitor, 'hi', t: 0));
      expect(
        startsNewTurn(a.current, r(CaptionSpeaker.visitor, 'still', t: kTurnPauseThresholdMs + 1)),
        isTrue,
      );
    });

    test('a quick continuation extends the turn', () {
      final a = TurnAccumulator()..apply(r(CaptionSpeaker.visitor, 'hi', t: 0));
      expect(startsNewTurn(a.current, r(CaptionSpeaker.visitor, 'hi there', t: 200)), isFalse);
    });
  });

  group('TurnAccumulator', () {
    test('extends a partial without concatenating across boundaries', () {
      final a = TurnAccumulator()
        ..apply(r(CaptionSpeaker.visitor, 'delivery', t: 0))
        ..apply(r(CaptionSpeaker.visitor, 'delivery for', t: 300));
      expect(a.turns.length, 1);
      expect(a.turns.single.text, 'delivery for');
    });

    test('produces separate labeled turns on speaker change', () {
      final a = TurnAccumulator()
        ..apply(r(CaptionSpeaker.visitor, 'hi', t: 0))
        ..apply(r(CaptionSpeaker.resident, 'hello', t: 100));
      expect(a.turns.map((t) => t.speaker).toList(),
          [CaptionSpeaker.visitor, CaptionSpeaker.resident]);
    });

    test('finalizeForPersistence keeps a trailing partial as provisional null', () {
      final a = TurnAccumulator()..apply(r(CaptionSpeaker.visitor, 'unfinished', t: 0));
      final turns = a.finalizeForPersistence();
      expect(turns.single.provisional, isTrue);
      expect(turns.single.confidence, isNull);
    });

    test('a finalized turn locks and the next result starts a new turn', () {
      final a = TurnAccumulator()
        ..apply(r(CaptionSpeaker.visitor, 'done', isFinal: true, t: 0, confidence: 0.9))
        ..apply(r(CaptionSpeaker.visitor, 'next', t: 100));
      expect(a.turns.length, 2);
      expect(a.turns.first.confidence, 0.9);
    });
  });
}
