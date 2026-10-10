// HIGH-06: every primary control exposes a real screen-reader tap action.
// Before the fix, the controls merged their inner button away with
// excludeSemantics and never reinstated SemanticsAction.tap, so TalkBack
// double-tap activation was unreliable on the product's hero actions. These
// tests assert hasAction(SemanticsAction.tap) on each control via the shared
// helper; they fail if excludeSemantics is restored without an onTap.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/design/components/primary_action_card.dart';
import 'package:threshold/design/components/status_banner.dart';
import 'package:threshold/design/theme.dart';
import 'package:threshold/reply/outbound_mode.dart';
import 'package:threshold/reply/reply_bar.dart';
import 'package:threshold/reply/reply_controller.dart';
import 'package:threshold/reply/reply_port.dart';
import 'package:threshold/session/conversation_screen.dart';
import 'package:threshold/session/session_controller.dart';
import 'package:threshold/session/session_port.dart';

import '../support/semantics_matchers.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: ThresholdTheme.light(), home: Scaffold(body: child));

void main() {
  group('Primary controls expose a tap action (HIGH-06)', () {
    testWidgets('PrimaryActionCard', (tester) async {
      final handle = tester.ensureSemantics();
      var tapped = false;
      await tester.pumpWidget(_wrap(
        PrimaryActionCard(
          key: const ValueKey('hero'),
          icon: Icons.doorbell_outlined,
          label: 'Answer the door',
          onPressed: () => tapped = true,
        ),
      ));
      await tester.pump();
      expectHasTapAction(tester, find.byType(PrimaryActionCard));
      // The control still activates on a tap (the inner InkWell is reachable).
      await tester.tap(find.byType(PrimaryActionCard));
      await tester.pump();
      expect(tapped, isTrue);
      handle.dispose();
    });

    testWidgets('StatusBanner action button', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(
        StatusBanner(
          message: 'Replies unavailable on this device.',
          variant: StatusVariant.warning,
          action: StatusBannerAction(
            label: 'Open Ring app',
            buttonKey: const ValueKey('banner-action'),
            onPressed: () {},
          ),
        ),
      ));
      await tester.pump();
      expectHasTapAction(tester, find.byKey(const ValueKey('banner-action')));
      handle.dispose();
    });

    testWidgets('reply bar send and suggestion buttons', (tester) async {
      final handle = tester.ensureSemantics();
      final controller = ReplyController(
        port: FakeReplyPort(),
        outbound: OutboundModeMachine()..applyProbe(ProbeResult.success),
      );
      await tester.pumpWidget(_wrap(ReplyBar(
        controller: controller,
        contextualSuggestions: const <String>['Thanks'],
      )));
      await tester.pump();
      expectHasTapAction(tester, find.byKey(const ValueKey('reply-send')));
      // A suggestion button also carries a tap action.
      expectHasTapAction(tester, find.widgetWithText(FilledButton, 'Thanks'));
      handle.dispose();
    });

    testWidgets('conversation screen end-session control', (tester) async {
      final handle = tester.ensureSemantics();
      final controller = SessionController(port: FakeSessionPort());
      await controller.open(deviceId: 'front-door');
      await tester.pumpWidget(_wrap(ConversationScreen(controller: controller)));
      await tester.pumpAndSettle();
      expectHasTapAction(tester, find.byKey(const ValueKey('end-session')));
      handle.dispose();
      controller.dispose();
    });
  });
}
