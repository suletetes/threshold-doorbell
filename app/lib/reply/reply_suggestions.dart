// Reply suggestion composition (Task 15, FR-6.1, FR-7.2, FR-7.5; AT-7). The
// reply bar offers at most 3 contextual suggestions (Bedrock in Clarity Mode via
// /replies, or on-device in Privacy Mode) PLUS the fixed safe set, and free text
// is always available (FR-7.5). This pure helper composes the final button set
// so the reply bar is never empty (FR-7.5) and never shows more than 3 dynamic
// suggestions (FR-7.1). The fixed safe set is always appended and deduplicated.

import 'ondevice_suggestions.dart';

/// The maximum number of dynamic (contextual) suggestions shown (FR-7.1).
const int kMaxContextualSuggestions = 3;

/// A composed reply-bar button set: up to 3 contextual suggestions followed by
/// the fixed safe set, with duplicates removed. Free text is a separate input,
/// always available (FR-7.5), so it is not part of this list.
List<String> composeReplyButtons(List<String> contextual) {
  final out = <String>[];
  for (final s in contextual) {
    if (out.length >= kMaxContextualSuggestions) break;
    final t = s.trim();
    if (t.isEmpty) continue;
    if (!out.contains(t)) out.add(t);
  }
  // Always append the fixed safe set so the bar is never empty (FR-7.2, FR-7.5).
  for (final s in kFixedSafeReplies) {
    if (!out.contains(s)) out.add(s);
  }
  return out;
}
