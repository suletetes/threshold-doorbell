// P2-4: contextual suggestions are wired. Privacy Mode produces on-device
// suggestions and NEVER calls Bedrock (FR-7.1a); Clarity Mode consults Bedrock.

import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/reply/ondevice_suggestions.dart';
import 'package:threshold/reply/suggestion_provider.dart';
import 'package:threshold/session/session_state.dart';

void main() {
  group('SuggestionProvider mode routing (P2-4, FR-7.1a; AT-8, AT-21)', () {
    test('Privacy Mode uses on-device suggestions and NEVER calls Bedrock', () async {
      final bedrock = FakeBedrockSuggestionPort();
      final provider = SuggestionProvider(bedrock: bedrock);
      final out = await provider.suggestionsFor(
        'I have a package delivery',
        mode: SessionCaptionMode.privacy,
      );
      // Bedrock was never touched (no transcript text left the device).
      expect(bedrock.callCount, 0);
      expect(bedrock.calls, isEmpty);
      // The result matches the on-device generator exactly.
      expect(out, onDeviceSuggestions('I have a package delivery'));
      expect(out, isNotEmpty);
      expect(out.length <= kMaxOnDeviceSuggestions, isTrue);
    });

    test('Clarity Mode consults Bedrock', () async {
      final bedrock = FakeBedrockSuggestionPort(scripted: <String>['A', 'B']);
      final provider = SuggestionProvider(bedrock: bedrock);
      final out = await provider.suggestionsFor(
        'hello',
        mode: SessionCaptionMode.clarity,
      );
      expect(bedrock.callCount, 1);
      expect(bedrock.calls.single, 'hello');
      expect(out, <String>['A', 'B']);
    });

    test('Clarity Mode caps contextual suggestions at 3 (FR-7.1)', () async {
      final bedrock = FakeBedrockSuggestionPort(scripted: <String>['a', 'b', 'c', 'd', 'e']);
      final provider = SuggestionProvider(bedrock: bedrock);
      final out = await provider.suggestionsFor('x', mode: SessionCaptionMode.clarity);
      expect(out.length, 3);
    });

    test('Privacy Mode never calls Bedrock even across repeated requests', () async {
      final bedrock = FakeBedrockSuggestionPort();
      final provider = SuggestionProvider(bedrock: bedrock);
      for (final text in <String>['who is there', 'package', 'help please']) {
        await provider.suggestionsFor(text, mode: SessionCaptionMode.privacy);
      }
      expect(bedrock.callCount, 0);
    });

    test('Clarity Mode falls back to on-device on a slow Bedrock (LOW-04)', () async {
      final provider = SuggestionProvider(bedrock: _SlowBedrock());
      final out = await provider.suggestionsFor(
        'I have a package',
        mode: SessionCaptionMode.clarity,
      );
      // The 2s timeout fired and the on-device set was used, so the result is
      // non-empty and the request did not hang.
      expect(out, isNotEmpty);
      expect(out, contains('Please leave it at the door'));
    });

    test('Clarity Mode falls back to on-device when Bedrock throws (LOW-04)', () async {
      final provider = SuggestionProvider(bedrock: _ThrowingBedrock());
      final out = await provider.suggestionsFor(
        'who is this',
        mode: SessionCaptionMode.clarity,
      );
      expect(out, isNotEmpty);
    });

    test('Clarity Mode strips dashes from Bedrock suggestions (LOW-04, NFR-10)', () async {
      final provider = SuggestionProvider(
        bedrock: FakeBedrockSuggestionPort(scripted: const <String>['Leave it \u2014 thanks']),
      );
      final out = await provider.suggestionsFor('hi', mode: SessionCaptionMode.clarity);
      expect(out.single.contains('\u2014'), isFalse);
      expect(out.single.contains('\u2013'), isFalse);
    });
  });
}

/// A Bedrock port that never resolves within the timeout window (LOW-04).
class _SlowBedrock implements BedrockSuggestionPort {
  @override
  Future<List<String>> suggest(String visitorText) =>
      Future<List<String>>.delayed(const Duration(seconds: 30), () => const <String>['too late']);
}

/// A Bedrock port that always throws (LOW-04).
class _ThrowingBedrock implements BedrockSuggestionPort {
  @override
  Future<List<String>> suggest(String visitorText) async => throw StateError('backend down');
}
