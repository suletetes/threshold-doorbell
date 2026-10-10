import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/captions/caption_styling.dart';

void main() {
  group('Caption confidence styling (FR-5.3, FR-5.3a, AT-4)', () {
    test('a partial result is always provisional (FR-5.3)', () {
      expect(emphasisForPartial(), CaptionEmphasis.provisional);
    });

    test('a finalized token below 0.6 is de-emphasized (FR-5.3a)', () {
      expect(emphasisForFinalToken(0.0), CaptionEmphasis.lowConfidence);
      expect(emphasisForFinalToken(0.59), CaptionEmphasis.lowConfidence);
    });

    test('a finalized token at or above 0.6 is normal (FR-5.3a)', () {
      expect(emphasisForFinalToken(0.6), CaptionEmphasis.normal);
      expect(emphasisForFinalToken(0.99), CaptionEmphasis.normal);
      expect(emphasisForFinalToken(1.0), CaptionEmphasis.normal);
    });

    test('the 0.6 boundary is inclusive of normal', () {
      // Exactly at the threshold renders normal, not de-emphasized.
      expect(
          emphasisForFinalToken(kConfidenceThreshold), CaptionEmphasis.normal);
    });

    test('a finalized token with null confidence is provisional (FR-5.7)', () {
      expect(emphasisForFinalToken(null), CaptionEmphasis.provisional);
    });

    test('emphasisForToken branches on isFinal', () {
      const token = CaptionToken(text: 'hi', confidence: 0.3);
      expect(
          emphasisForToken(token, isFinal: false), CaptionEmphasis.provisional);
      expect(emphasisForToken(token, isFinal: true),
          CaptionEmphasis.lowConfidence);
    });

    test('isDeEmphasized covers provisional and low confidence', () {
      expect(isDeEmphasized(CaptionEmphasis.provisional), isTrue);
      expect(isDeEmphasized(CaptionEmphasis.lowConfidence), isTrue);
      expect(isDeEmphasized(CaptionEmphasis.normal), isFalse);
    });
  });
}
