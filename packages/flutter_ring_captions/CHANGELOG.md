# Changelog

All notable changes to this package are documented here. The format is based on
Keep a Changelog, and this package aims to follow semantic versioning.

## 0.1.0

Initial release of the accessibility-oriented, dependency-light caption and
reply-bridge logic developed inside the Threshold doorbell project.

- Caption confidence styling (`caption_styling.dart`): map a partial or a
  finalized token to a rendering emphasis using a 0.6 confidence threshold.
  Invalid confidences (NaN or out of range) are handled defensively.
- Turn segmentation (`turn_segmentation.dart`): accumulate engine results into
  ordered, labeled speaker turns. `CaptionTurn.copyWith` can clear a confidence
  via the `clearConfidence` flag. Input is validated (non-empty text, monotonic
  timestamps). The cumulative-partial contract on `CaptionResult.text` is
  documented.
- Sticky outbound mode (`outbound_mode.dart`): a per-session capability-probe
  state machine whose result is sticky, with a documented no-op for injection
  attempts once the session is captions-only.
- Reply bridge helpers (`reply_bridge.dart`): assemble a never-empty reply bar,
  strip an extended set of forbidden dash characters, preserve line breaks, cap
  suggestion length, and dedupe case- and punctuation-insensitively.
- Value types (`CaptionToken`, `CaptionResult`, `CaptionTurn`,
  `OutboundModeSnapshot`) implement `==`, `hashCode`, and `toString` for change
  detection and readable test output.
- Library source depends only on `package:meta`, not the Flutter SDK.
