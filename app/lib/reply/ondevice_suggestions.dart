// On-device suggestion generator (Task 18, FR-7.1a, FR-7.2, FR-7.5; AT-8, AT-21).
// In Privacy Mode the app SHALL NOT call Bedrock and SHALL NOT send transcript
// text off the device (FR-7.1a). Suggestions are produced entirely on-device
// from the fixed safe set plus local keyword-matched templates. Pure logic, so
// the matching and the zero-egress guarantee are unit-testable. No dashes appear
// in any suggestion (NFR-10).

/// The fixed safe-reply set (FR-7.2). Always offered, in every mode. Dash-free.
const List<String> kFixedSafeReplies = <String>[
  'Please leave it at the door',
  "I can't come to the door right now",
  'Please come back later',
];

/// A local keyword template: if any trigger word appears in the visitor text,
/// the suggestion is offered. Entirely local; no model, no network (FR-7.1a).
class _KeywordTemplate {
  const _KeywordTemplate(this.triggers, this.suggestion);
  final List<String> triggers;
  final String suggestion;
}

// Local, fixed templates. These never leave the device and never call a model.
const List<_KeywordTemplate> _templates = <_KeywordTemplate>[
  _KeywordTemplate(<String>['package', 'delivery', 'parcel', 'dropoff'],
      'Please leave it at the door'),
  _KeywordTemplate(
      <String>['sign', 'signature'], 'Please leave it at the door'),
  _KeywordTemplate(<String>['who', 'name'], 'Who is this please'),
  _KeywordTemplate(<String>['help', 'emergency'], 'Is everything okay'),
  _KeywordTemplate(<String>['later', 'busy', 'moment'], 'One moment please'),
];

/// Maximum suggestions offered (FR-7.1: at most 3). The reply bar is never
/// empty because the fixed safe set is always available (FR-7.5).
const int kMaxOnDeviceSuggestions = 3;

/// Generate up to 3 on-device suggestions for [visitorText] (FR-7.1a). Keyword
/// matches are offered first, then the fixed safe set fills any remaining slots,
/// so the result is never empty (FR-7.5) and never exceeds 3 (FR-7.1). All
/// matching is local; [visitorText] is never transmitted (FR-7.1a).
List<String> onDeviceSuggestions(String visitorText) {
  // Tokenize on word boundaries so a trigger matches a whole word only. The old
  // substring `contains` matched "who" inside "whole" and "sign" inside
  // "design", offering the wrong template (LOW-03).
  final words = visitorText
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toSet();
  final out = <String>[];
  void add(String s) {
    if (out.length >= kMaxOnDeviceSuggestions) return;
    if (!out.contains(s)) out.add(s);
  }

  for (final t in _templates) {
    if (t.triggers.any(words.contains)) {
      add(t.suggestion);
    }
  }
  // Fill remaining slots with the fixed safe set so the bar is never empty.
  for (final s in kFixedSafeReplies) {
    add(s);
  }
  return out;
}
