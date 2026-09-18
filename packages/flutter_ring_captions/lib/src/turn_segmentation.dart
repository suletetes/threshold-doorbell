// Turn segmentation. Pure logic that decides when an incoming caption result
// starts a NEW labeled turn versus extends the current one, so a change of
// speaker, a pause beyond a threshold, or an engine segmentation boundary
// produces separate labeled turns rather than one run-on block. Extracted from
// the Threshold project.

import 'package:flutter/foundation.dart';

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
  final String text;
  final bool isFinal;
  final int timestampMs;
  final bool segmentBoundary;
  final double? confidence;
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

  CaptionTurn copyWith({
    String? text,
    bool? isFinal,
    int? lastUpdatedMs,
    double? confidence,
    bool? provisional,
  }) {
    return CaptionTurn(
      speaker: speaker,
      text: text ?? this.text,
      isFinal: isFinal ?? this.isFinal,
      startedAtMs: startedAtMs,
      lastUpdatedMs: lastUpdatedMs ?? this.lastUpdatedMs,
      confidence: confidence ?? this.confidence,
      provisional: provisional ?? this.provisional,
    );
  }
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
        confidence: result.isFinal ? result.confidence : null,
        provisional: !result.isFinal,
      ),
    );
  }

  /// Persist-time finalization: any still-provisional trailing turn is kept as
  /// provisional with null confidence.
  List<CaptionTurn> finalizeForPersistence() {
    if (_turns.isNotEmpty && current!.provisional) {
      final CaptionTurn cur = _turns.removeLast();
      _turns.add(cur.copyWith(confidence: null, provisional: true, isFinal: false));
    }
    return turns;
  }
}
