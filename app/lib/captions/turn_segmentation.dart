// Turn segmentation (Task 13, FR-5.5, FR-5.7; AT-4). Pure logic that decides
// when an incoming caption result starts a NEW labeled turn versus extends the
// current one, so a change of speaker, a pause beyond a threshold, or an engine
// segmentation boundary produces separate labeled turns rather than one run-on
// block. Unit-testable without any audio or widget tree.

import 'package:flutter/foundation.dart';

/// Who is speaking in a turn.
enum CaptionSpeaker { visitor, resident }

/// The pause, in milliseconds, after which a new result starts a new turn even
/// for the same speaker (FR-5.5 "pause or segmentation boundary").
const int kTurnPauseThresholdMs = 1500;

/// An incoming caption result from the engine.
@immutable
class CaptionResult {
  const CaptionResult({
    required this.speaker,
    required this.text,
    required this.isFinal,
    required this.timestampMs,
    this.segmentBoundary = false,
    this.confidence,
    this.wordConfidences,
  });

  final CaptionSpeaker speaker;
  final String text;
  final bool isFinal;
  final int timestampMs;

  /// The engine signaled an explicit segmentation boundary before this result.
  final bool segmentBoundary;

  /// Turn-level confidence when finalized; null while provisional (FR-5.7).
  final double? confidence;

  /// Per-word confidences aligned to the whitespace-split words of [text], when
  /// the engine reports them (FR-5.3a). Null when the engine only reports a
  /// turn-level confidence, in which case per-token styling falls back to the
  /// turn confidence. Carried through so per-token emphasis is real, not every
  /// token painted with the turn's own value (MED-02).
  final List<double>? wordConfidences;
}

/// A labeled turn accumulated from one or more results.
@immutable
class CaptionTurn {
  const CaptionTurn({
    required this.speaker,
    required this.text,
    required this.isFinal,
    required this.startedAtMs,
    required this.lastUpdatedMs,
    this.confidence,
    this.provisional = true,
    this.wordConfidences,
  });

  final CaptionSpeaker speaker;
  final String text;
  final bool isFinal;
  final int startedAtMs;
  final int lastUpdatedMs;
  final double? confidence;

  /// Per-word confidences aligned to the words of [text] when the engine
  /// reports them (FR-5.3a, MED-02). Null when only a turn-level confidence is
  /// available; the caption surface then styles every token by the turn value.
  final List<double>? wordConfidences;

  /// True while the turn is not yet finalized (FR-5.7).
  final bool provisional;

  /// Returns a copy with the given overrides. Because [confidence] is nullable,
  /// passing `confidence: null` cannot by itself distinguish "keep the current
  /// value" from "clear it", so an explicit [clearConfidence] flag forces a null
  /// confidence. This keeps the public contract identical to the extracted
  /// flutter_ring_captions package (MED-21) and ensures a turn downgraded to
  /// provisional loses its stale confidence instead of rendering uncertain text
  /// as certain (FR-5.7).
  CaptionTurn copyWith({
    String? text,
    bool? isFinal,
    int? lastUpdatedMs,
    double? confidence,
    bool? provisional,
    List<double>? wordConfidences,
    bool clearConfidence = false,
    bool clearWordConfidences = false,
  }) {
    return CaptionTurn(
      speaker: speaker,
      text: text ?? this.text,
      isFinal: isFinal ?? this.isFinal,
      startedAtMs: startedAtMs,
      lastUpdatedMs: lastUpdatedMs ?? this.lastUpdatedMs,
      confidence: clearConfidence ? null : (confidence ?? this.confidence),
      provisional: provisional ?? this.provisional,
      wordConfidences: clearWordConfidences
          ? null
          : (wordConfidences ?? this.wordConfidences),
    );
  }
}

/// Decide whether [result] should start a new turn given the [current] turn.
/// A new turn starts when: there is no current turn; the speaker changed; the
/// current turn is already finalized; the engine signaled a segment boundary; or
/// the gap since the last update exceeds the pause threshold (FR-5.5).
bool startsNewTurn(CaptionTurn? current, CaptionResult result) {
  if (current == null) return true;
  if (current.speaker != result.speaker) return true;
  if (current.isFinal) return true;
  if (result.segmentBoundary) return true;
  if (result.timestampMs - current.lastUpdatedMs > kTurnPauseThresholdMs) {
    return true;
  }
  return false;
}

/// Accumulates results into an ordered list of labeled turns (FR-5.5). This is
/// the pure state the caption UI renders. Persisting a session while a turn is
/// unfinalized leaves it provisional with null confidence (FR-5.7).
class TurnAccumulator {
  final List<CaptionTurn> _turns = <CaptionTurn>[];

  List<CaptionTurn> get turns => List.unmodifiable(_turns);

  CaptionTurn? get current => _turns.isEmpty ? null : _turns.last;

  /// Apply one incoming result, either starting a new turn or extending the
  /// current one. Never concatenates across a boundary (FR-5.5).
  void apply(CaptionResult result) {
    if (startsNewTurn(current, result)) {
      // Before starting the next turn, close out any open provisional turn so
      // it does not linger on screen as "Still listening" forever when the
      // speaker simply paused mid-utterance (MED-01, probe P12).
      _closeOpenProvisionalTurn(nextResult: result);
      _turns.add(
        CaptionTurn(
          speaker: result.speaker,
          text: result.text,
          isFinal: result.isFinal,
          startedAtMs: result.timestampMs,
          lastUpdatedMs: result.timestampMs,
          confidence: result.isFinal ? result.confidence : null,
          wordConfidences: result.isFinal ? result.wordConfidences : null,
          provisional: !result.isFinal,
        ),
      );
      return;
    }
    // Extend the current (still-provisional) turn.
    final CaptionTurn cur = _turns.removeLast();
    _turns.add(
      cur.copyWith(
        // A partial replaces the in-progress text; a final also replaces then locks.
        text: result.text,
        isFinal: result.isFinal,
        lastUpdatedMs: result.timestampMs,
        confidence: result.isFinal ? result.confidence : null,
        // A partial clears any stale confidence so it never renders as certain.
        clearConfidence: !result.isFinal,
        // Per-word confidences only exist once finalized; a partial clears them.
        wordConfidences: result.isFinal ? result.wordConfidences : null,
        clearWordConfidences: !result.isFinal,
        provisional: !result.isFinal,
      ),
    );
  }

  /// Close an open provisional turn when a pause or boundary starts the next
  /// one (MED-01). An empty provisional turn is dropped; a provisional turn with
  /// text is finalized (locked, no longer "Still listening") with null
  /// confidence, since the engine never confirmed it. Called only when the
  /// current turn is still provisional; a finalized turn is left untouched.
  void _closeOpenProvisionalTurn({required CaptionResult nextResult}) {
    final CaptionTurn? cur = current;
    if (cur == null || !cur.provisional) return;
    if (cur.text.trim().isEmpty) {
      _turns.removeLast(); // nothing worth keeping
      return;
    }
    final CaptionTurn open = _turns.removeLast();
    _turns.add(
      open.copyWith(isFinal: true, provisional: false, clearConfidence: true),
    );
  }

  /// Persist-time finalization (FR-5.7): any still-provisional trailing turn is
  /// kept as provisional with null confidence. Returns the final turn list.
  List<CaptionTurn> finalizeForPersistence() {
    if (_turns.isNotEmpty && current!.provisional) {
      final CaptionTurn cur = _turns.removeLast();
      _turns.add(
        cur.copyWith(clearConfidence: true, provisional: true, isFinal: false),
      );
    }
    return turns;
  }
}
