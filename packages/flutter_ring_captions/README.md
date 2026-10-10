# flutter_ring_captions

Accessibility-oriented, dependency-light pure logic for live captions and a
reply bridge on a Ring style video doorbell. Extracted from the
[Threshold](../../README.md) project, a two-way captioned doorbell built for deaf
and hard-of-hearing residents.

The package is deliberately free of device, network, and SDK dependencies. It is
the decision logic you wire to your own WebRTC session, speech-to-text engine,
and text-to-speech. That keeps it fully unit-testable and reusable in any
live-caption UI.

## What it gives you

- **Caption confidence styling** (`caption_styling.dart`): map a partial or a
  finalized token to a rendering emphasis (provisional, low confidence, normal)
  using a 0.6 confidence threshold, so a screen reader friendly UI can show what
  is certain and what is not.
- **Turn segmentation** (`turn_segmentation.dart`): accumulate engine results
  into ordered, labeled speaker turns. A speaker change, a pause beyond a
  threshold, or an engine segment boundary starts a new turn instead of one
  run-on block. Persist-time finalization keeps a trailing partial provisional.
- **Sticky outbound mode** (`outbound_mode.dart`): a per-session state machine
  for a capability probe whose result is sticky. If a later injection fails the
  session degrades to captions-only and does not auto-recover; the next session
  re-probes.
- **Reply bridge helpers** (`reply_bridge.dart`): assemble a reply bar that is
  never empty (a fixed safe set backs any model suggestions) and strip forbidden
  em-dash and en-dash characters from generated copy before display.

## Install

This package is developed inside the Threshold monorepo. To use it from another
Flutter app, add a path or git dependency:

```yaml
dependencies:
  flutter_ring_captions:
    git:
      url: https://github.com/suletetes/threshold-doorbell
      path: packages/flutter_ring_captions
```

## Usage

```dart
import 'package:flutter_ring_captions/flutter_ring_captions.dart';

// Style a finalized token.
final emphasis = emphasisForFinalToken(0.55); // CaptionEmphasis.lowConfidence

// Build a reply bar that is never empty and never shows a dash.
final replies = replyBarSuggestions(<Object?>['Sure thing, I will be right down']);

// Track sticky outbound capability for a session.
final mode = OutboundModeMachine()..applyProbe(ProbeResult.success);
mode.recordInjection(success: false); // degrades to captions-only for the session
```

## Accessibility notes

- No information is conveyed by color or audio alone: emphasis is a semantic
  enum you can map to weight, opacity, and a text label.
- The reply layer removes em-dash and en-dash characters, which some screen
  readers announce inconsistently, in favor of plain punctuation.

## License

MIT. See [LICENSE](LICENSE).
