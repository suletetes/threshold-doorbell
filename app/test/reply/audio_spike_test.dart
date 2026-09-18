import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/reply/audio_spike.dart';

// Verifies the WebView<->Flutter bridge contract for the ARCH-1 audio spike
// (Task 2). The WebRTC path itself is device/Ring-bound, but the message parsing
// and sticky-verdict logic are pure and fully tested here.
void main() {
  group('SpikeMessage.parse', () {
    test('parses a well-formed log message', () {
      final m = SpikeMessage.parse('{"type":"log","line":"hello"}');
      expect(m.type, 'log');
      expect(m.data['line'], 'hello');
    });

    test('rejects a non-object payload', () {
      expect(() => SpikeMessage.parse('[]'), throwsFormatException);
      expect(() => SpikeMessage.parse('"x"'), throwsFormatException);
    });

    test('rejects a missing or empty type', () {
      expect(() => SpikeMessage.parse('{"line":"x"}'), throwsFormatException);
      expect(() => SpikeMessage.parse('{"type":""}'), throwsFormatException);
    });
  });

  group('verdictFrom', () {
    test('probe true -> pass', () {
      final m = SpikeMessage.parse('{"type":"probe","outboundAvailable":true}');
      expect(m.verdictFrom(), SpikeVerdict.pass);
    });

    test('probe false -> fail', () {
      final m = SpikeMessage.parse('{"type":"probe","outboundAvailable":false}');
      expect(m.verdictFrom(), SpikeVerdict.fail);
    });

    test('verdict kind pass/fail map through', () {
      expect(SpikeMessage.parse('{"type":"verdict","kind":"pass"}').verdictFrom(),
          SpikeVerdict.pass);
      expect(SpikeMessage.parse('{"type":"verdict","kind":"fail"}').verdictFrom(),
          SpikeVerdict.fail);
    });

    test('log and state messages do not change the verdict', () {
      expect(SpikeMessage.parse('{"type":"log","line":"x"}').verdictFrom(), isNull);
      expect(SpikeMessage.parse('{"type":"state","state":"PROBING"}').verdictFrom(), isNull);
    });

    test('unknown probe value does not change the verdict', () {
      expect(SpikeMessage.parse('{"type":"probe"}').verdictFrom(), isNull);
    });
  });
}
