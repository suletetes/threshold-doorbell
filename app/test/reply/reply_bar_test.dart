import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/reply/outbound_mode.dart';
import 'package:threshold/reply/reply_bar.dart';
import 'package:threshold/reply/reply_controller.dart';
import 'package:threshold/reply/reply_port.dart';

OutboundModeMachine _twoWay() =>
    OutboundModeMachine()..applyProbe(ProbeResult.success);

Widget _wrap(ReplyController c, List<String> suggestions) => MaterialApp(
      home: Scaffold(
        body: ReplyBar(controller: c, contextualSuggestions: suggestions),
      ),
    );

void main() {
  group('ReplyBar widget (Task 15, FR-6.1, 6.3, 7.5; AT-5, AT-7)', () {
    testWidgets('renders suggestion chips plus a free-text field',
        (tester) async {
      final port = FakeReplyPort();
      final c = ReplyController(port: port, outbound: _twoWay());
      await tester.pumpWidget(_wrap(c, const <String>['Coming now']));
      await tester.pump();
      expect(find.byKey(const ValueKey('reply-bar')), findsOneWidget);
      expect(find.byKey(const ValueKey('reply-freetext')), findsOneWidget);
      expect(find.text('Coming now'), findsOneWidget);
      // Fixed safe set always present (FR-7.2, FR-7.5).
      expect(find.text('Please leave it at the door'), findsOneWidget);
      c.dispose();
    });

    testWidgets(
        'tapping a suggestion speaks it and shows the speaking banner (FR-6.3)',
        (tester) async {
      // Gate playback so the controller stays in SPEAKING_AT_DOOR while we
      // assert the banner is actually on screen. The old version only checked
      // that speak() was called and never that the banner rendered.
      final gate = Completer<void>();
      final port = FakeReplyPort(playbackGate: gate.future);
      final c = ReplyController(port: port, outbound: _twoWay());
      await tester.pumpWidget(_wrap(c, const <String>[]));
      await tester.pump();
      await tester.tap(find.text('Please come back later'));
      await tester.pump(); // enter synthesizing then speakingAtDoor

      // The speaking banner is visible with its dash-free in-flight label while
      // the reply plays, and the suggestion buttons are gone (the whole bar is
      // the speaking banner in this state).
      expect(c.state, ReplyState.speakingAtDoor);
      expect(find.text(kSpeakingAtDoorLabel), findsOneWidget);
      expect(find.text('Please leave it at the door'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(port.spokenTexts.contains('Please come back later'), isTrue);
      c.dispose();
    });

    testWidgets('free-text send speaks the typed reply', (tester) async {
      final port = FakeReplyPort();
      final c = ReplyController(port: port, outbound: _twoWay());
      await tester.pumpWidget(_wrap(c, const <String>[]));
      await tester.pump();
      await tester.enterText(
          find.byKey(const ValueKey('reply-freetext')), 'On my way');
      await tester.tap(find.byKey(const ValueKey('reply-send')));
      await tester.pumpAndSettle();
      expect(port.spokenTexts.contains('On my way'), isTrue);
      expect(c.turns.single.source, ReplySource.freetext);
      c.dispose();
    });

    testWidgets('the bar is hidden when outbound is unavailable (FR-6.4)',
        (tester) async {
      final outbound = OutboundModeMachine()..applyProbe(ProbeResult.failure);
      final port = FakeReplyPort();
      final c = ReplyController(port: port, outbound: outbound);
      await tester.pumpWidget(_wrap(c, const <String>[]));
      await tester.pump();
      expect(find.byKey(const ValueKey('reply-bar')), findsNothing);
      c.dispose();
    });

    testWidgets(
        'renders contextual suggestions from the controller (MED-13, FR-7.1a)',
        (tester) async {
      final port = FakeReplyPort();
      final c = ReplyController(port: port, outbound: _twoWay());
      await tester.pumpWidget(_wrap(c, const <String>[]));
      await tester.pump();
      // No controller suggestions yet: only the fixed safe set shows.
      expect(find.text('Thanks, one moment'), findsNothing);
      // The composition root pushes suggestions onto the controller; the bar
      // repaints and shows them (it reads the controller, not just the field).
      c.setContextualSuggestions(const <String>['Thanks, one moment']);
      await tester.pump();
      expect(find.text('Thanks, one moment'), findsOneWidget);
      c.dispose();
    });

    testWidgets('controls carry Semantics labels (G4)', (tester) async {
      final handle = tester.ensureSemantics();
      final port = FakeReplyPort();
      final c = ReplyController(port: port, outbound: _twoWay());
      await tester.pumpWidget(_wrap(c, const <String>[]));
      await tester.pump();
      expect(find.bySemanticsLabel('Type a reply'), findsOneWidget);
      expect(find.bySemanticsLabel('Send reply'), findsOneWidget);
      expect(find.bySemanticsLabel('Reply: Please come back later'),
          findsOneWidget);
      handle.dispose();
      c.dispose();
    });
  });
}
