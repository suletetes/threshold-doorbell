// Reply bridge helpers. Pure logic that keeps the reply bar safe and never
// empty, and strips forbidden dashes from any generated reply before display.
// Extracted from the Threshold project; the actual audio injection binding is
// left to the host app (WebView AudioContext or a native PCM source).

/// Forbidden dash characters that must never reach a user-facing string. The
/// reply-rendering layer strips these from generated copy before display.
const List<String> kForbiddenDashes = <String>['\u2014', '\u2013', '\u2012', '\u2015'];

/// The fixed safe-reply set: always offered, in every mode. Dash-free.
const List<String> kFixedSafeReplies = <String>[
  'Please leave it at the door',
  "I can't come to the door right now",
  'Please come back later',
];

/// Maximum suggestions offered at once.
const int kMaxSuggestions = 3;

/// Replace any forbidden dash in [text] with a spaced hyphen, collapsing extra
/// whitespace, so no em-dash or en-dash ever reaches the UI.
String stripDashes(String text) {
  var out = text;
  for (final dash in kForbiddenDashes) {
    out = out.replaceAll(dash, ' - ');
  }
  // Collapse any runs of whitespace introduced by the replacement.
  return out.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Sanitize model-suggested replies: strip dashes, drop empties, dedupe, and cap
/// at [kMaxSuggestions]. Non-string entries are ignored defensively.
List<String> sanitizeSuggestions(List<Object?> raw) {
  final seen = <String>{};
  final out = <String>[];
  for (final item in raw) {
    if (item is! String) continue;
    final cleaned = stripDashes(item);
    if (cleaned.isEmpty || seen.contains(cleaned)) continue;
    seen.add(cleaned);
    out.add(cleaned);
    if (out.length >= kMaxSuggestions) break;
  }
  return out;
}

/// Produce the final reply-bar suggestions: sanitized model replies first, then
/// the fixed safe set fills any remaining slots so the bar is never empty and
/// never exceeds [kMaxSuggestions].
List<String> replyBarSuggestions(List<Object?> modelReplies) {
  final out = sanitizeSuggestions(modelReplies);
  for (final safe in kFixedSafeReplies) {
    if (out.length >= kMaxSuggestions) break;
    if (!out.contains(safe)) out.add(safe);
  }
  return out;
}
