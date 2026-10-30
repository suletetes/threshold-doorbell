// Ringing screen tests: the incoming-doorbell screen must give the resident the
// three choices and time out to missed, all without audio.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/session/ringing_screen.dart';

Widget _host(RingingScreen screen) => MaterialApp(home: screen);

void main() {
  group('RingingScreen (incoming doorbell, FR-3.3)', () {
    testWidgets('shows the three actions', (tester) async {
      await tester.pumpWidget(_host(RingingScreen(
        onAnswer: () {},
        onComing: () {},
        onDecline: () {},
        onMissed: () {},
      )));
      expect(find.byKey(const ValueKey('ring-answer')), findsOneWidget);
      expect(find.byKey(const ValueKey('ring-coming')), findsOneWidget);
      expect(find.byKey(const ValueKey('ring-decline')), findsOneWidget);
      expect(find.text('Someone is at your door'), findsOneWidget);
    });

    testWidgets('Answer fires onAnswer once', (tester) async {
      var answers = 0;
      await tester.pumpWidget(_host(RingingScreen(
        onAnswer: () => answers++,
        onComing: () {},
        onDecline: () {},
        onMissed: () {},
      )));
      await tester.tap(find.byKey(const ValueKey('ring-answer')));
      await tester.pump();
      expect(answers, 1);
    });

    testWidgets('Decline fires onDecline', (tester) async {
      var declines = 0;
      await tester.pumpWidget(_host(RingingScreen(
        onAnswer: () {},
        onComing: () {},
        onDecline: () => declines++,
        onMissed: () {},
      )));
      await tester.tap(find.byKey(const ValueKey('ring-decline')));
      await tester.pump();
      expect(declines, 1);
    });

    testWidgets('I am coming fires onComing', (tester) async {
      var coming = 0;
      await tester.pumpWidget(_host(RingingScreen(
        onAnswer: () {},
        onComing: () => coming++,
        onDecline: () {},
        onMissed: () {},
      )));
      await tester.tap(find.byKey(const ValueKey('ring-coming')));
      await tester.pump();
      expect(coming, 1);
    });

    testWidgets('times out to missed after kRingTimeout', (tester) async {
      var missed = 0;
      await tester.pumpWidget(_host(RingingScreen(
        onAnswer: () {},
        onComing: () {},
        onDecline: () {},
        onMissed: () => missed++,
      )));
      // Advance past the 30s timeout.
      await tester.pump(kRingTimeout + const Duration(seconds: 1));
      expect(missed, 1);
      // A later action after missing does not double-fire.
      await tester.tap(find.byKey(const ValueKey('ring-answer')));
      await tester.pump();
      expect(missed, 1);
    });

    testWidgets('an action fires only once even on repeated taps',
        (tester) async {
      var answers = 0;
      await tester.pumpWidget(_host(RingingScreen(
        onAnswer: () => answers++,
        onComing: () {},
        onDecline: () {},
        onMissed: () {},
      )));
      await tester.tap(find.byKey(const ValueKey('ring-answer')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ring-answer')));
      await tester.pump();
      expect(answers, 1);
    });
  });
}
