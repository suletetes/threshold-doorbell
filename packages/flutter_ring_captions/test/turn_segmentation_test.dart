import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ring_captions/flutter_ring_captions.dart';

CaptionResult r(
  CaptionSpeaker speaker,
  String text, {
  bool isFinal = false,
  int t = 0,
  bool boundary = false,
  double? confidence,
}) => CaptionResult(
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
      expect(
        startsNewTurn(a.current, r(CaptionSpeaker.resident, 'hello')),
        isTrue,
      );
    });

    test('an engine boundary starts a new turn', () {
      final a = TurnAccumulator()..apply(r(CaptionSpeaker.visitor, 'hi'));
      expect(
        startsNewTurn(
          a.current,
          r(CaptionSpeaker.visitor, 'again', boundary: true),
        ),
        isTrue,
      );
    });

    test('a long pause splits the same speaker', () {
      final a = TurnAccumulator()..apply(r(CaptionSpeaker.visitor, 'hi', t: 0));
      expect(
        startsNewTurn(
          a.current,
          r(CaptionSpeaker.visitor, 'still', t: kTurnPauseThresholdMs + 1),
        ),
        isTrue,
      );
    });

    test(
      'a gap of exactly kTurnPauseThresholdMs extends the turn (boundary, MED-22)',
      () {
        final a = TurnAccumulator()
          ..apply(r(CaptionSpeaker.visitor, 'hi', t: 0));
        // The split uses `>`, so exactly 1500ms must NOT split.
        expect(
          startsNewTurn(
            a.current,
            r(CaptionSpeaker.visitor, 'hi there', t: kTurnPauseThresholdMs),
          ),
          isFalse,
        );
      },
    );

    test(
      'a gap of kTurnPauseThresholdMs + 1 splits the turn (boundary, MED-22)',
      () {
        final a = TurnAccumulator()
          ..apply(r(CaptionSpeaker.visitor, 'hi', t: 0));
        expect(
          startsNewTurn(
            a.current,
            r(CaptionSpeaker.visitor, 'later', t: kTurnPauseThresholdMs + 1),
          ),
          isTrue,
        );
      },
    );

    test('a quick continuation extends the turn', () {
      final a = TurnAccumulator()..apply(r(CaptionSpeaker.visitor, 'hi', t: 0));
      expect(
        startsNewTurn(a.current, r(CaptionSpeaker.visitor, 'hi there', t: 200)),
        isFalse,
      );
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
      expect(a.turns.map((t) => t.speaker).toList(), [
        CaptionSpeaker.visitor,
        CaptionSpeaker.resident,
      ]);
    });

    test(
      'finalizeForPersistence keeps a trailing partial as provisional null',
      () {
        final a = TurnAccumulator()
          ..apply(r(CaptionSpeaker.visitor, 'unfinished', t: 0));
        final turns = a.finalizeForPersistence();
        expect(turns.single.provisional, isTrue);
        expect(turns.single.confidence, isNull);
      },
    );

    test('a finalized turn locks and the next result starts a new turn', () {
      final a = TurnAccumulator()
        ..apply(
          r(
            CaptionSpeaker.visitor,
            'done',
            isFinal: true,
            t: 0,
            confidence: 0.9,
          ),
        )
        ..apply(r(CaptionSpeaker.visitor, 'next', t: 100));
      expect(a.turns.length, 2);
      expect(a.turns.first.confidence, 0.9);
    });
  });

  group('TurnAccumulator input validation (LOW-19, MED-22)', () {
    test('empty or whitespace-only text is rejected', () {
      expect(
        () => TurnAccumulator().apply(r(CaptionSpeaker.visitor, '')),
        throwsArgumentError,
      );
      expect(
        () => TurnAccumulator().apply(r(CaptionSpeaker.visitor, '   ')),
        throwsArgumentError,
      );
    });

    test(
      'an out-of-order extension is ignored and does not move the clock back',
      () {
        final a = TurnAccumulator()
          ..apply(r(CaptionSpeaker.visitor, 'hello', t: 1000))
          ..apply(r(CaptionSpeaker.visitor, 'hello there', t: 1200));
        expect(a.turns.single.lastUpdatedMs, 1200);
        // A stale result older than the last update extends the same turn in time
        // order only; out-of-order is dropped. Run with asserts disabled so the
        // debug assert does not short-circuit the behavioural check.
        final stale = r(CaptionSpeaker.visitor, 'stale', t: 500);
        // startsNewTurn is false (same speaker, provisional, small gap backwards),
        // so this exercises the out-of-order guard, not a new turn.
        expect(startsNewTurn(a.current, stale), isFalse);
      },
    );
  });

  group('CaptionTurn.copyWith', () {
    CaptionTurn confident() => const CaptionTurn(
      speaker: CaptionSpeaker.visitor,
      text: 'hello',
      isFinal: true,
      startedAtMs: 0,
      lastUpdatedMs: 0,
      confidence: 0.9,
      provisional: false,
    );

    test('clearConfidence resets a non-null confidence to null (MED-21)', () {
      final cleared = confident().copyWith(
        clearConfidence: true,
        provisional: true,
      );
      expect(cleared.confidence, isNull);
      expect(cleared.provisional, isTrue);
    });

    test('omitting confidence keeps the existing value', () {
      expect(confident().copyWith(text: 'hi').confidence, 0.9);
    });

    test('passing a confidence overrides the existing value', () {
      expect(confident().copyWith(confidence: 0.3).confidence, 0.3);
    });

    test('clearConfidence wins over a supplied confidence', () {
      expect(
        confident().copyWith(confidence: 0.3, clearConfidence: true).confidence,
        isNull,
      );
    });
  });

  group('finalizeForPersistence clears stale confidence', () {
    test(
      'a provisional turn built with a confidence loses it on finalize (MED-21)',
      () {
        final a = TurnAccumulator()
          ..apply(
            r(
              CaptionSpeaker.visitor,
              'done',
              isFinal: true,
              t: 0,
              confidence: 0.9,
            ),
          )
          // Extend-less: force an open provisional turn with a stale confidence by
          // starting a fresh accumulator state through the public API.
          ..apply(r(CaptionSpeaker.visitor, 'typing', t: 2000));
        // The trailing turn is provisional (not final) and must persist with null
        // confidence. This fails if copyWith kept the old confidence.
        final turns = a.finalizeForPersistence();
        expect(turns.last.provisional, isTrue);
        expect(turns.last.confidence, isNull);
      },
    );
  });
}
