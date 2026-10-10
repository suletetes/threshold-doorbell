// Reply bridge helpers. Pure logic that keeps the reply bar safe and never
// empty, and strips forbidden dashes from any generated reply before display.
// Extracted from the Threshold project; the actual audio injection binding is
// left to the host app (WebView AudioContext or a native PCM source).

/// Forbidden dash characters that must never reach a user-facing string. The
/// reply-rendering layer strips these from generated copy before display. The
/// set covers the common em/en/figure/horizontal-bar dashes plus visually
/// identical glyphs a model can emit: two- and three-em dash (U+2E3A, U+2E3B),
/// small/fullwidth hyphen-minus (U+FE58, U+FE63, U+FF0D) and the minus sign
/// (U+2212), so an em-dash-looking character cannot slip through (LOW-21).
const List<String> kForbiddenDashes = <String>[
  '\u2014', // em dash
  '\u2013', // en dash
  '\u2012', // figure dash
  '\u2015', // horizontal bar
  '\u2E3A', // two-em dash
  '\u2E3B', // three-em dash
  '\uFE58', // small em dash
  '\uFE63', // small hyphen-minus
  '\uFF0D', // fullwidth hyphen-minus
  '\u2212', // minus sign
];

/// Maximum length of a single sanitized suggestion. A longer model reply is
/// truncated so it cannot blow up the reply-bar layout (LOW-21).
const int kMaxSuggestionLength = 80;

/// The fixed safe-reply set: always offered, in every mode. Dash-free.
const List<String> kFixedSafeReplies = <String>[
  'Please leave it at the door',
  "I can't come to the door right now",
  'Please come back later',
];

/// Maximum suggestions offered at once.
const int kMaxSuggestions = 3;

/// Replace any forbidden dash in [text] with a spaced hyphen, collapsing runs of
/// horizontal whitespace, so no em-dash or en-dash ever reaches the UI. Line
/// breaks are preserved: a multi-line reply that contains no dash is returned
/// with its lines intact, only trimmed and with intra-line spacing collapsed
/// (LOW-21). Each line is trimmed; leading and trailing blank lines are dropped.
String stripDashes(String text) {
  var out = text;
  for (final dash in kForbiddenDashes) {
    out = out.replaceAll(dash, ' - ');
  }
  // Collapse runs of horizontal whitespace (spaces, tabs) within each line but
  // keep newlines, then trim each line and drop empty leading/trailing lines.
  final lines = out
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[^\S\n]+'), ' ').trim())
      .toList();
  while (lines.isNotEmpty && lines.first.isEmpty) {
    lines.removeAt(0);
  }
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines.join('\n');
}

/// Normalize a suggestion for dedupe comparison only: lowercase, strip trailing
/// punctuation and collapse all whitespace, so "Please come back later" and
/// "please come back later." are treated as the same suggestion (LOW-22). The
/// displayed string is the original cleaned text, not this normalized form.
String _dedupeKey(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'[^\w\s]'), '')
    .trim();

/// Sanitize model-suggested replies: strip dashes, drop empties, truncate to
/// [kMaxSuggestionLength], dedupe case- and punctuation-insensitively, and cap
/// at [kMaxSuggestions]. Non-string entries are ignored defensively.
List<String> sanitizeSuggestions(List<Object?> raw) {
  final seen = <String>{};
  final out = <String>[];
  for (final item in raw) {
    if (item is! String) continue;
    var cleaned = stripDashes(item);
    if (cleaned.length > kMaxSuggestionLength) {
      cleaned = cleaned.substring(0, kMaxSuggestionLength).trimRight();
    }
    final key = _dedupeKey(cleaned);
    if (cleaned.isEmpty || key.isEmpty || seen.contains(key)) continue;
    seen.add(key);
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
  final seen = out.map(_dedupeKey).toSet();
  for (final safe in kFixedSafeReplies) {
    if (out.length >= kMaxSuggestions) break;
    if (seen.add(_dedupeKey(safe))) out.add(safe);
  }
  return out;
}
