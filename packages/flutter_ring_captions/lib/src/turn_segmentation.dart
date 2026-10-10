// Turn segmentation. Pure logic that decides when an incoming caption result
// starts a NEW labeled turn versus extends the current one, so a change of
// speaker, a pause beyond a threshold, or an engine segmentation boundary
// produces separate labeled turns rather than one run-on block. Extracted from
// the Threshold project.

import 'package:meta/meta.dart';

/// Who is speaking in a turn.
enum CaptionSpeaker { visitor, resident }

/// The pause, in milliseconds, after which a new result starts a new turn even
/// for the same speaker.
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
  });

  final CaptionSpeaker speaker;

  /// The caption text for this result.
  ///
  /// Contract (LOW-20): [text] is CUMULATIVE for a turn, not a delta. When a
  /// result extends the current turn, [TurnAccumulator.apply] REPLACES the
  /// turn's text with this value rather than appending to it, so the engine must
  /// deliver each partial as the full text of the turn so far. An engine that
  /// emits only the newly recognized words (a delta) would lose earlier words.
  /// Adapt such an engine by accumulating deltas before constructing a result.
  final String text;
  final bool isFinal;

  /// Monotonic timestamp in milliseconds. Results are expected in time order;
  /// see [TurnAccumulator.apply] for how out-of-order input is handled (LOW-19).
  final int timestampMs;
  final bool segmentBoundary;
  final double? confidence;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CaptionResult &&
          other.speaker == speaker &&
          other.text == text &&
          other.isFinal == isFinal &&
          other.timestampMs == timestampMs &&
          other.segmentBoundary == segmentBoundary &&
          other.confidence == confidence;

  @override
  int get hashCode => Object.hash(
        speaker,
        text,
        isFinal,
        timestampMs,
        segmentBoundary,
        confidence,
      );

  @override
  String toString() => 'CaptionResult(speaker: $speaker, text: $text, '
      'isFinal: $isFinal, timestampMs: $timestampMs, '
      'segmentBoundary: $segmentBoundary, confidence: $confidence)';
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
  });

  final CaptionSpeaker speaker;
  final String text;
  final bool isFinal;
  final int startedAtMs;
  final int lastUpdatedMs;
  final double? confidence;
  final bool provisional;

  /// Returns a copy with the given overrides. Because [confidence] is nullable,
  /// passing `confidence: null` cannot by itself distinguish "keep the current
  /// value" from "clear it", so an explicit [clearConfidence] flag forces the
  /// result to a null confidence. This matters for finalization, where a turn
  /// that is downgraded to provisional must lose its stale confidence rather
  /// than silently keep it and render uncertain text as certain (MED-21).
  CaptionTurn copyWith({
    String? text,
    bool? isFinal,
    int? lastUpdatedMs,
    double? confidence,
    bool? provisional,
    bool clearConfidence = false,
  }) {
    return CaptionTurn(
      speaker: speaker,
      text: text ?? this.text,
      isFinal: isFinal ?? this.isFinal,
      startedAtMs: startedAtMs,
      lastUpdatedMs: lastUpdatedMs ?? this.lastUpdatedMs,
      confidence: clearConfidence ? null : (confidence ?? this.confidence),
      provisional: provisional ?? this.provisional,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CaptionTurn &&
          other.speaker == speaker &&
          other.text == text &&
          other.isFinal == isFinal &&
          other.startedAtMs == startedAtMs &&
          other.lastUpdatedMs == lastUpdatedMs &&
          other.confidence == confidence &&
          other.provisional == provisional;

  @override
  int get hashCode => Object.hash(
        speaker,
        text,
        isFinal,
        startedAtMs,
        lastUpdatedMs,
        confidence,
        provisional,
      );

  @override
  String toString() => 'CaptionTurn(speaker: $speaker, text: $text, '
      'isFinal: $isFinal, startedAtMs: $startedAtMs, '
      'lastUpdatedMs: $lastUpdatedMs, confidence: $confidence, '
      'provisional: $provisional)';
}

/// Decide whether [result] should start a new turn given the [current] turn.
bool startsNewTurn(CaptionTurn? current, CaptionResult result) {
  if (current == null) return true;
  if (current.speaker != result.speaker) return true;
  if (current.isFinal) return true;
  if (result.segmentBoundary) return true;
  if (result.timestampMs - current.lastUpdatedMs > kTurnPauseThresholdMs) return true;
  return false;
}

/// Accumulates results into an ordered list of labeled turns.
class TurnAccumulator {
  final List<CaptionTurn> _turns = <CaptionTurn>[];

  List<CaptionTurn> get turns => List.unmodifiable(_turns);
  CaptionTurn? get current => _turns.isEmpty ? null : _turns.last;

  void apply(CaptionResult result) {
    // Input validation (LOW-19). Reject empty or whitespace-only text so the
    // accumulator never produces an empty labeled turn.
    if (result.text.trim().isEmpty) {
      throw ArgumentError.value(
        result.text,
        'result.text',
        'caption result text must not be empty',
      );
    }
    // Guard against out-of-order (non-monotonic) timestamps when extending the
    // current turn: a result older than the turn's last update would otherwise
    // move lastUpdatedMs backwards and corrupt the pause-threshold logic. Such a
    // stale result is ignored. A debug assert surfaces the upstream ordering bug.
    final CaptionTurn? openTurn = current;
    if (openTurn != null &&
        !startsNewTurn(openTurn, result) &&
        result.timestampMs < openTurn.lastUpdatedMs) {
      assert(
        false,
        'out-of-order caption result: ${result.timestampMs}ms < '
        'last update ${openTurn.lastUpdatedMs}ms',
      );
      return;
    }
    if (startsNewTurn(current, result)) {
      _turns.add(
        CaptionTurn(
          speaker: result.speaker,
          text: result.text,
          isFinal: result.isFinal,
          startedAtMs: result.timestampMs,
          lastUpdatedMs: result.timestampMs,
          confidence: result.isFinal ? result.confidence : null,
          provisional: !result.isFinal,
        ),
      );
      return;
    }
    final CaptionTurn cur = _turns.removeLast();
    _turns.add(
      cur.copyWith(
        text: result.text,
        isFinal: result.isFinal,
        lastUpdatedMs: result.timestampMs,
        // A finalized result carries its confidence; a partial clears any stale
        // one so provisional text never renders as certain (MED-21).
        confidence: result.isFinal ? result.confidence : null,
        clearConfidence: !result.isFinal,
        provisional: !result.isFinal,
      ),
    );
  }

  /// Persist-time finalization: any still-provisional trailing turn is kept as
  /// provisional with null confidence.
  List<CaptionTurn> finalizeForPersistence() {
    if (_turns.isNotEmpty && current!.provisional) {
      final CaptionTurn cur = _turns.removeLast();
      _turns.add(cur.copyWith(clearConfidence: true, provisional: true, isFinal: false));
    }
    return turns;
  }
}
