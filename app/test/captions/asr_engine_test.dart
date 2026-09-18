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

    test('transmits zero bytes: audio and transcript never leave the device (NFR-4, AT-8)', () {
      final e = FixtureAsrEngine();
      e.feed(<int>[1, 2, 3, 4]);
      e.feed(<int>[5, 6, 7, 8]);
      expect(e.bytesTransmitted, 0);
      expect(e.bytesProcessed, 8); // processed locally only
    });

    test('an unready engine reports not ready (Privacy Mode gated until verified)', () {
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
