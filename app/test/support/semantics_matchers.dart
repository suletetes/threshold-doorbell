// Shared test helper for HIGH-06: every primary control must expose a real
// screen-reader tap action so TalkBack / VoiceOver double-tap activation works.
// The audit found the controls wrapped the inner button in
// Semantics(button: true, excludeSemantics: true, ...), which stripped the
// SemanticsAction.tap, so the hero actions of an accessibility product had no
// tap action.
//
// expectHasTapAction(tester, finder) asserts the semantics node found by
// [finder] carries SemanticsAction.tap. Use it on every primary control.

import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether [node]'s action bitmask includes [SemanticsAction.tap].
bool nodeHasTap(SemanticsNode node) =>
    (node.getSemanticsData().actions & SemanticsAction.tap.index) != 0;

/// Assert that the control found by [finder] reports a screen-reader tap action
/// (HIGH-06). [reason] is included in the failure message.
void expectHasTapAction(
  WidgetTester tester,
  Finder finder, {
  String? reason,
}) {
  expect(finder, findsOneWidget,
      reason: 'control not found: ${reason ?? finder}');
  final node = tester.getSemantics(finder);
  expect(
    nodeHasTap(node),
    isTrue,
    reason:
        reason ?? 'control must expose SemanticsAction.tap (HIGH-06): $finder',
  );
}
