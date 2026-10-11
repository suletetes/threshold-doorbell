import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/captions/asr_engine.dart';

void main() {
  group('FixtureAsrEngine (Task 18, FR-5.2, NFR-4; AT-8)', () {
    test('is ready by default and emits scripted partial then final', () {
      final e = FixtureAsrEngine();
      expect(e.isReady, isTrue);
      final first = e.feed(<int>[1, 2, 3, 4]);
      expect(first.single.isFinal, isFalse);
      final second = e.feed(<int>[5, 6, 7, 8]);
      expect(second.single.isFinal, isTrue);
      expect(second.single.confidence, 0.88);
    });

    test(
        'processes every fed byte locally while transmitting none (NFR-4, AT-8)',
        () {
      final e = FixtureAsrEngine();
      // Feed several frames of differing sizes.
      e.feed(<int>[1, 2, 3, 4]);
      e.feed(<int>[5, 6, 7, 8, 9]);
      e.feed(<int>[10]);
      // Every byte fed is accounted for locally: processed tracks the frames
      // exactly, so the engine really did consume the audio rather than ignore
      // it. If feed() started counting those same bytes as transmitted (an
      // egress regression) this would fail.
      expect(e.bytesProcessed, 4 + 5 + 1);
      expect(e.bytesTransmitted, 0);
      expect(
        e.bytesTransmitted,
        lessThan(e.bytesProcessed),
        reason: 'audio is processed on-device but never transmitted',
      );
    });

    test(
        'an unready engine reports not ready (Privacy Mode gated until verified)',
        () {
      final e = FixtureAsrEngine(ready: false);
      expect(e.isReady, isFalse);
    });

    test('a custom script drives deterministic results', () {
      final e = FixtureAsrEngine(
        script: const <OnDeviceResult>[
          OnDeviceResult(isFinal: true, transcript: 'stop', confidence: 0.5),
        ],
      );
      expect(e.feed(<int>[0]).single.transcript, 'stop');
      // Past the script, no more results (no crash, no egress).
      expect(e.feed(<int>[0]), isEmpty);
      expect(e.bytesTransmitted, 0);
    });
  });
}
