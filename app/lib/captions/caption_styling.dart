// Caption confidence styling (Task 13, FR-5.3, FR-5.3a; AT-4). Pure logic that
// maps a caption token or partial to a rendering emphasis, so the styling rules
// are unit-testable without a widget tree. The widget layer consumes
// CaptionEmphasis to pick opacity/weight; this file owns the decision.

import 'package:flutter/foundation.dart';

/// The confidence threshold below which a finalized token is de-emphasized
/// (FR-5.3a). At or above this value a token renders in normal style.
const double kConfidenceThreshold = 0.6;

/// How a caption fragment should be emphasized.
enum CaptionEmphasis {
  /// Provisional: a partial result, whole-fragment de-emphasized (FR-5.3).
  provisional,

  /// Finalized but low confidence (< 0.6): de-emphasized (FR-5.3a).
  lowConfidence,

  /// Finalized and confident (>= 0.6): normal style (FR-5.3a).
  normal,
}

/// A single caption token with an optional confidence. Confidence is null while
/// unfinalized (FR-5.7); a partial has no per-token confidence at all.
@immutable
class CaptionToken {
  const CaptionToken({required this.text, this.confidence});

  final String text;
  final double? confidence;
}

/// Emphasis for a whole PARTIAL result. Per FR-5.3, a partial has no per-token
/// confidence and the whole partial is rendered provisional (never "certain").
CaptionEmphasis emphasisForPartial() => CaptionEmphasis.provisional;

/// Emphasis for a single FINALIZED token given its confidence (FR-5.3a).
/// A null confidence on a finalized token is treated as provisional (it was
/// persisted unfinalized per FR-5.7) rather than assumed certain.
CaptionEmphasis emphasisForFinalToken(double? confidence) {
  if (confidence == null) return CaptionEmphasis.provisional;
  return confidence >= kConfidenceThreshold
      ? CaptionEmphasis.normal
      : CaptionEmphasis.lowConfidence;
}

/// Emphasis for a token that may be part of a partial or a finalized result.
/// `isFinal` distinguishes the two cases so the caller does not have to branch.
CaptionEmphasis emphasisForToken(CaptionToken token, {required bool isFinal}) {
  if (!isFinal) return CaptionEmphasis.provisional;
  return emphasisForFinalToken(token.confidence);
}

/// True when a fragment should be visually de-emphasized (provisional or low
/// confidence). Convenience for the widget layer.
bool isDeEmphasized(CaptionEmphasis emphasis) =>
    emphasis == CaptionEmphasis.provisional || emphasis == CaptionEmphasis.lowConfidence;
