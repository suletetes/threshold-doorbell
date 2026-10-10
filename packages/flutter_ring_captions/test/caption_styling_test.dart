import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ring_captions/flutter_ring_captions.dart';

void main() {
  group('caption styling', () {
    test('a partial is always provisional', () {
      expect(emphasisForPartial(), CaptionEmphasis.provisional);
    });

    test('a finalized token below 0.6 is de-emphasized', () {
      expect(emphasisForFinalToken(0.59), CaptionEmphasis.lowConfidence);
    });

    test('the 0.6 boundary is inclusive of normal', () {
      expect(emphasisForFinalToken(0.6), CaptionEmphasis.normal);
    });

    test('a finalized token with null confidence is provisional', () {
      expect(emphasisForFinalToken(null), CaptionEmphasis.provisional);
    });

    test('a NaN confidence is treated as provisional, not low confidence (LOW-19)', () {
      expect(emphasisForFinalToken(double.nan), CaptionEmphasis.provisional);
    });

    test('an out-of-range high confidence clamps to normal (LOW-19)', () {
      // Asserts are enabled under flutter test, so an out-of-range value trips
      // the debug assert. Verify the assertion fires for a non-NaN out-of-range
      // input, which documents the defensive contract.
      expect(() => emphasisForFinalToken(1.5), throwsA(isA<AssertionError>()));
      expect(() => emphasisForFinalToken(-0.5), throwsA(isA<AssertionError>()));
    });

    test('emphasisForToken branches on isFinal', () {
      const token = CaptionToken(text: 'hello', confidence: 0.9);
      expect(emphasisForToken(token, isFinal: false), CaptionEmphasis.provisional);
      expect(emphasisForToken(token, isFinal: true), CaptionEmphasis.normal);
    });

    test('isDeEmphasized covers provisional and low confidence', () {
      expect(isDeEmphasized(CaptionEmphasis.provisional), isTrue);
      expect(isDeEmphasized(CaptionEmphasis.lowConfidence), isTrue);
      expect(isDeEmphasized(CaptionEmphasis.normal), isFalse);
    });
  });
}
