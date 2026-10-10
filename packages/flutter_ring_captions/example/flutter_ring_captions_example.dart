// ignore_for_file: avoid_print
//
// A minimal, runnable example of the flutter_ring_captions decision logic.
// It wires nothing to a device: it just drives the pure functions and prints
// the results, so you can see how a host app would consume them.
//
// Run with: dart run example/flutter_ring_captions_example.dart

import 'package:flutter_ring_captions/flutter_ring_captions.dart';

void main() {
  // 1. Caption confidence styling.
  print('partial emphasis: ${emphasisForPartial()}');
  print('final 0.55 emphasis: ${emphasisForFinalToken(0.55)}');
  print('final 0.90 emphasis: ${emphasisForFinalToken(0.90)}');

  // 2. Turn segmentation: accumulate engine results into labeled turns.
  final accumulator = TurnAccumulator()
    ..apply(
      const CaptionResult(
        speaker: CaptionSpeaker.visitor,
        text: 'delivery',
        isFinal: false,
        timestampMs: 0,
      ),
    )
    ..apply(
      const CaptionResult(
        speaker: CaptionSpeaker.visitor,
        text: 'delivery for you',
        isFinal: true,
        timestampMs: 300,
        confidence: 0.92,
      ),
    );
  for (final turn in accumulator.turns) {
    print(
      'turn: ${turn.speaker.name} says "${turn.text}" '
      '(final: ${turn.isFinal}, confidence: ${turn.confidence})',
    );
  }

  // 3. Reply bar: never empty, never shows a forbidden dash.
  final replies = replyBarSuggestions(<Object?>[
    'Sure thing, I will be right down',
    'hold on\u2014one sec',
  ]);
  print('reply bar: $replies');

  // 4. Sticky outbound mode for a session.
  final mode = OutboundModeMachine()..applyProbe(ProbeResult.success);
  print('outbound available: ${mode.outboundAvailable}');
  mode.recordInjection(success: false);
  print('after injection failure, captions only: ${mode.isCaptionsOnly}');
}
