// Contextual reply-suggestion provider (Task 18 wiring, FR-7.1, FR-7.1a; AT-8,
// AT-21). The reply bar shows up to 3 contextual suggestions. Which SOURCE
// produces them depends on the session caption mode:
//
//   * Clarity Mode: the backend /replies endpoint (Bedrock) may be consulted,
//     since transcript text already leaves the device for cloud ASR.
//   * Privacy Mode: suggestions are produced ENTIRELY on-device via
//     onDeviceSuggestions; Bedrock is NEVER called and no transcript text
//     leaves the handset (FR-7.1a, NFR-4).
//
// This provider owns that routing so the wiring the audit found missing exists
// in production and is testable: a Privacy-Mode request must never touch the
// Bedrock path. The Bedrock call is network-bound and sits behind a port with a
// fake; the on-device path is the pure onDeviceSuggestions function.

import 'dart:async';

import '../session/session_state.dart';
import 'ondevice_suggestions.dart';

/// Backend Bedrock suggestion port (Clarity Mode only, FR-7.1). The live binding
/// calls POST /replies; the fake records calls so tests can assert Privacy Mode
/// never invokes it.
abstract class BedrockSuggestionPort {
  /// Return up to 3 contextual suggestions for [visitorText] (Clarity Mode).
  Future<List<String>> suggest(String visitorText);
}

/// Deterministic fake. Records every call so tests can prove Privacy Mode never
/// calls Bedrock (FR-7.1a).
class FakeBedrockSuggestionPort implements BedrockSuggestionPort {
  FakeBedrockSuggestionPort({List<String>? scripted})
      : _scripted = scripted ?? const <String>['Thanks, one moment', 'Leave it there please'];

  final List<String> _scripted;

  /// Every visitor text passed to [suggest], in order (assertion helper).
  final List<String> calls = <String>[];
  int callCount = 0;

  @override
  Future<List<String>> suggest(String visitorText) async {
    callCount++;
    calls.add(visitorText);
    return List<String>.from(_scripted);
  }
}

/// Routes contextual-suggestion generation by the session caption mode (FR-7.1a).
class SuggestionProvider {
  SuggestionProvider({required BedrockSuggestionPort bedrock}) : _bedrock = bedrock;

  final BedrockSuggestionPort _bedrock;

  /// Produce up to 3 contextual suggestions for [visitorText] in [mode]. In
  /// Privacy Mode this is computed on-device and NEVER calls Bedrock (FR-7.1a);
  /// in Clarity Mode it consults the Bedrock port (design §5.3).
  Future<List<String>> suggestionsFor(
    String visitorText, {
    required SessionCaptionMode mode,
  }) async {
    if (mode == SessionCaptionMode.privacy) {
      // Entirely on-device; no network, no Bedrock (FR-7.1a).
      return onDeviceSuggestions(visitorText);
    }
    // Clarity Mode: Bedrock may be consulted; cap to 3 (FR-7.1). Bound the call
    // to 2 seconds and fall back to the on-device suggestions on timeout or
    // error so a slow or failing backend never blocks the reply bar (LOW-04).
    List<String> out;
    try {
      out = await _bedrock
          .suggest(visitorText)
          .timeout(kBedrockSuggestionTimeout);
    } catch (_) {
      return onDeviceSuggestions(visitorText);
    }
    // Strip any dash a model may have produced (NFR-10) and drop empties.
    final cleaned = <String>[];
    for (final s in out) {
      final stripped = stripDashes(s).trim();
      if (stripped.isNotEmpty) cleaned.add(stripped);
    }
    return cleaned.take(kMaxOnDeviceSuggestions).toList();
  }
}

/// The time budget for a Bedrock suggestion call before falling back to the
/// on-device set (LOW-04).
const Duration kBedrockSuggestionTimeout = Duration(seconds: 2);

/// Replace em and en dashes a model may emit with a plain hyphen so a suggestion
/// never violates the dash-free UI copy rule (NFR-10, LOW-04).
String stripDashes(String s) => s.replaceAll('\u2014', '-').replaceAll('\u2013', '-');
