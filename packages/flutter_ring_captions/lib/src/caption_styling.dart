// Caption confidence styling. Pure logic mapping a caption token or partial to a
// rendering emphasis so styling rules are unit-testable without a widget tree.
// Extracted from the Threshold project for reuse in any live-caption UI.

import 'package:flutter/foundation.dart';

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
}

/// Emphasis for a whole PARTIAL result: always provisional.
CaptionEmphasis emphasisForPartial() => CaptionEmphasis.provisional;

/// Emphasis for a single FINALIZED token given its confidence. A null confidence
/// on a finalized token is treated as provisional rather than assumed certain.
CaptionEmphasis emphasisForFinalToken(double? confidence) {
  if (confidence == null) return CaptionEmphasis.provisional;
  return confidence >= kConfidenceThreshold
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
    emphasis == CaptionEmphasis.provisional || emphasis == CaptionEmphasis.lowConfidence;
