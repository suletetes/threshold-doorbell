// Caption confidence styling. Pure logic mapping a caption token or partial to a
// rendering emphasis so styling rules are unit-testable without a widget tree.
// Extracted from the Threshold project for reuse in any live-caption UI.

import 'package:meta/meta.dart';

/// Confidence threshold below which a finalized token is de-emphasized. At or
/// above this value a token renders in normal style.
const double kConfidenceThreshold = 0.6;

/// How a caption fragment should be emphasized.
enum CaptionEmphasis {
  /// A partial result: whole fragment de-emphasized (provisional).
  provisional,

  /// Finalized but low confidence (< threshold): de-emphasized.
  lowConfidence,

  /// Finalized and confident (>= threshold): normal style.
  normal,
}

/// A single caption token with an optional confidence. Confidence is null while
/// unfinalized; a partial has no per-token confidence at all.
@immutable
class CaptionToken {
  const CaptionToken({required this.text, this.confidence});
  final String text;
  final double? confidence;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CaptionToken &&
          other.text == text &&
          other.confidence == confidence;

  @override
  int get hashCode => Object.hash(text, confidence);

  @override
  String toString() => 'CaptionToken(text: $text, confidence: $confidence)';
}

/// Emphasis for a whole PARTIAL result: always provisional.
CaptionEmphasis emphasisForPartial() => CaptionEmphasis.provisional;

/// Emphasis for a single FINALIZED token given its confidence. A null confidence
/// on a finalized token is treated as provisional rather than assumed certain.
///
/// Invalid input is handled defensively (LOW-19): a NaN confidence is treated as
/// unknown and rendered provisional rather than silently becoming lowConfidence,
/// and the value is clamped to the inclusive range [0, 1] before thresholding so
/// an out-of-range value cannot be read as "more certain than certain". In debug
/// builds an out-of-range (non-NaN) value also trips an assert to surface the
/// upstream bug.
CaptionEmphasis emphasisForFinalToken(double? confidence) {
  if (confidence == null) return CaptionEmphasis.provisional;
  if (confidence.isNaN) return CaptionEmphasis.provisional;
  assert(
    confidence >= 0.0 && confidence <= 1.0,
    'confidence must be within [0, 1], got $confidence',
  );
  final clamped = confidence.clamp(0.0, 1.0);
  return clamped >= kConfidenceThreshold
      ? CaptionEmphasis.normal
      : CaptionEmphasis.lowConfidence;
}

/// Emphasis for a token that may be part of a partial or a finalized result.
CaptionEmphasis emphasisForToken(CaptionToken token, {required bool isFinal}) {
  if (!isFinal) return CaptionEmphasis.provisional;
  return emphasisForFinalToken(token.confidence);
}

/// True when a fragment should be visually de-emphasized.
bool isDeEmphasized(CaptionEmphasis emphasis) =>
    emphasis == CaptionEmphasis.provisional ||
    emphasis == CaptionEmphasis.lowConfidence;
