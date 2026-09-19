// Reply bar presentation (UI/UX audit section 4, "Feedback states"): "Success:
// no success affordance at all. 'Speaking at your door' is a text state with no
// completion cue, which matters because the user cannot hear that the reply
// played."
//
// That sentence is the whole reason this file exists. For this product's users,
// the visual confirmation is the ONLY channel that carries the fact that a reply
// actually played at the door.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/design/colors.dart';
import 'package:threshold/design/components/components.dart';
import 'package:threshold/design/theme.dart';
import 'package:threshold/design/tokens.dart';
import 'package:threshold/reply/outbound_mode.dart';
import 'package:threshold/reply/reply_bar.dart';
import 'package:threshold/reply/reply_controller.dart';
import 'package:threshold/reply/reply_port.dart';

OutboundModeMachine _twoWay() => OutboundModeMachine()..applyProbe(ProbeResult.success);

/// A port that holds the reply in flight until the test releases it. FakeReplyPort
/// resolves in a microtask, so the speaking state is gone before the first pump
/// and cannot be observed.
class _BlockingReplyPort implements ReplyPort {
  final Completer<SpeakOutcome> _completer = Completer<SpeakOutcome>();
  final List<String> spokenTexts = <String>[];

  void finish(SpeakOutcome outcome) => _completer.complete(outcome);

  @override
  Future<SpeakOutcome> speak(String text) {
    spokenTexts.add(text);
    return _completer.future;
  }
}

Widget _host(ReplyController c, {List<String> suggestions = const <String>[]}) =>
    MaterialApp(
      theme: ThresholdTheme.dark(),
      home: Scaffold(
        body: ReplyBar(controller: c, contextualSuggestions: suggestions),
      ),
    );

void main() {
  group('A completed reply is confirmed visually (audit section 4)', () {
    testWidgets('sending a free-text reply shows the completion cue naming the reply',
        (tester) async {
      final c = ReplyController(port: FakeReplyPort(), outbound: _twoWay());
      await tester.pumpWidget(_host(c));
      await tester.pump();
      expect(find.byKey(const ValueKey('reply-played')), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('reply-freetext')), 'On my way');
      await tester.tap(find.byKey(const ValueKey('reply-send')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('reply-played')), findsOneWidget);
      expect(find.text(replyPlayedConfirmation('On my way')), findsOneWidget);
      c.dispose();
    });

    testWidgets('tapping a suggestion also confirms it played', (tester) async {
      final c = ReplyController(port: FakeReplyPort(), outbound: _twoWay());
      await tester.pumpWidget(_host(c));
      await tester.pump();
      await tester.tap(find.text('Please come back later'));
      await tester.pumpAndSettle();
      expect(
        find.text(replyPlayedConfirmation('Please come back later')),
        findsOneWidget,
      );
      c.dispose();
    });

    testWidgets('the cue uses the success role with a sound icon', (tester) async {
      final c = ReplyController(port: FakeReplyPort(), outbound: _twoWay());
      await tester.pumpWidget(_host(c));
      await tester.pump();
      await tester.tap(find.text('Please come back later'));
      await tester.pumpAndSettle();
      final banner = tester.widget<StatusBanner>(find.byKey(const ValueKey('reply-played')));
      expect(banner.variant, StatusVariant.success);
      expect(banner.icon, Icons.volume_up_outlined);
      final context = tester.element(find.byKey(const ValueKey('reply-played')));
      expect(
        StatusBanner.colorFor(context, StatusVariant.success),
        ThresholdSemanticColors.of(context).success,
      );
      c.dispose();
    });

    testWidgets('the cue is announced as a live region (G4)', (tester) async {
      final handle = tester.ensureSemantics();
      final c = ReplyController(port: FakeReplyPort(), outbound: _twoWay());
      await tester.pumpWidget(_host(c));
      await tester.pump();
      await tester.tap(find.text('Please come back later'));
      await tester.pumpAndSettle();
      final label = replyPlayedConfirmation('Please come back later');
      expect(find.bySemanticsLabel(label), findsOneWidget);
      expect(
        tester.widget<StatusBanner>(find.byKey(const ValueKey('reply-played'))).liveRegion,
        isTrue,
      );
      handle.dispose();
      c.dispose();
    });

    testWidgets('it persists rather than expiring, then retires when composing resumes',
        (tester) async {
      final c = ReplyController(port: FakeReplyPort(), outbound: _twoWay());
      await tester.pumpWidget(_host(c));
      await tester.pump();
      await tester.tap(find.text('Please come back later'));
      await tester.pumpAndSettle();
      // A cue that disappears on its own is a cue someone can miss.
      await tester.pump(const Duration(seconds: 10));
      expect(find.byKey(const ValueKey('reply-played')), findsOneWidget);

      // Typing the next reply retires it.
      await tester.enterText(find.byKey(const ValueKey('reply-freetext')), 'Th');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reply-played')), findsNothing);
      c.dispose();
    });

    testWidgets('a failed reply shows no completion cue', (tester) async {
      final port = FakeReplyPort(
        plan: <SpeakOutcome>[SpeakOutcome.ttsFailed, SpeakOutcome.ttsFailed],
      );
      final c = ReplyController(port: port, outbound: _twoWay());
      await tester.pumpWidget(_host(c));
      await tester.pump();
      await tester.tap(find.text('Please come back later'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reply-played')), findsNothing);
      c.dispose();
    });

    testWidgets('the cue animation collapses to zero under reduced motion',
        (tester) async {
      final c = ReplyController(port: FakeReplyPort(), outbound: _twoWay());
      await tester.pumpWidget(
        MaterialApp(
          theme: ThresholdTheme.dark(),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: Scaffold(
                body: ReplyBar(controller: c, contextualSuggestions: const <String>[]),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<AnimatedSize>(find.byType(AnimatedSize)).duration,
        Motion.instant,
      );
      c.dispose();
    });
  });

  group('The Speaking at your door state is preserved (FR-6.3)', () {
    testWidgets('it renders with the live role and no controls to resubmit with',
        (tester) async {
      final port = _BlockingReplyPort();
      final c = ReplyController(port: port, outbound: _twoWay());
      await tester.pumpWidget(_host(c));
      await tester.pump();
      // Hold the reply in flight so the speaking state is observable.
      final sending = c.send('Coming now', source: ReplySource.template);
      await tester.pump();
      expect(find.byKey(const ValueKey('speaking-banner')), findsOneWidget);
      expect(find.text(kSpeakingAtDoorLabel), findsOneWidget);
      // No send control exists while a reply plays, so it cannot be resubmitted.
      expect(find.byKey(const ValueKey('reply-send')), findsNothing);
      expect(find.byKey(const ValueKey('reply-freetext')), findsNothing);

      final context = tester.element(find.byKey(const ValueKey('speaking-banner')));
      final live = ThresholdSemanticColors.of(context).live;
      final decoration = tester
          .widget<DecoratedBox>(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('speaking-banner')),
                  matching: find.byType(DecoratedBox),
                )
                .first,
          )
          .decoration as BoxDecoration;
      expect(decoration.color!.a, 1.0);
      expect(decoration.border!.top.color, live);

      port.finish(SpeakOutcome.spoken);
      await sending;
      await tester.pumpAndSettle();
      c.dispose();
    });

    testWidgets('the speaking label keeps its live region (G4)', (tester) async {
      final handle = tester.ensureSemantics();
      final port = _BlockingReplyPort();
      final c = ReplyController(port: port, outbound: _twoWay());
      await tester.pumpWidget(_host(c));
      await tester.pump();
      final sending = c.send('Coming now', source: ReplySource.template);
      await tester.pump();
      expect(find.bySemanticsLabel(kSpeakingAtDoorLabel), findsOneWidget);
      port.finish(SpeakOutcome.spoken);
      await sending;
      await tester.pumpAndSettle();
      handle.dispose();
      c.dispose();
    });
  });

  group('Errors use the danger role (audit C2)', () {
    testWidgets('a TTS failure renders a danger banner, not pink text', (tester) async {
      final port = FakeReplyPort(
        plan: <SpeakOutcome>[SpeakOutcome.ttsFailed, SpeakOutcome.ttsFailed],
      );
      final c = ReplyController(port: port, outbound: _twoWay());
      await tester.pumpWidget(_host(c));
      await tester.pump();
      // send() then read the error before the bar resets itself.
      await c.send('Coming now', source: ReplySource.template);
      await tester.pump();
      expect(find.byKey(const ValueKey('reply-error')), findsOneWidget);
      final banner = tester.widget<StatusBanner>(find.byKey(const ValueKey('reply-error')));
      expect(banner.variant, StatusVariant.danger);
      expect(banner.message, c.errorMessage);
      c.dispose();
    });
  });

  group('Controls reach the 48dp floor (audit section 4, touch targets)', () {
    testWidgets('every suggestion and the send control are at least 48dp tall',
        (tester) async {
      final c = ReplyController(port: FakeReplyPort(), outbound: _twoWay());
      await tester.pumpWidget(_host(c, suggestions: const <String>['Coming now']));
      await tester.pump();
      final sizes = tester
          .widgetList<FilledButton>(find.byType(FilledButton))
          .map((b) => tester.getSize(find.byWidget(b)).height)
          .toList();
      expect(sizes, isNotEmpty);
      for (final height in sizes) {
        expect(height, greaterThanOrEqualTo(TouchTarget.minimum));
      }
      expect(
        tester.getSize(find.byKey(const ValueKey('reply-send'))).height,
        greaterThanOrEqualTo(TouchTarget.minimum),
      );
      c.dispose();
    });

    testWidgets('the send control gained an icon', (tester) async {
      final c = ReplyController(port: FakeReplyPort(), outbound: _twoWay());
      await tester.pumpWidget(_host(c));
      await tester.pump();
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      c.dispose();
    });
  });

  _reducedMotionGroup();

  group('Reply copy (NFR-10)', () {
    test('no dashes in the reply bar strings', () {
      for (final copy in <String>[
        kSpeakingAtDoorLabel,
        replyPlayedConfirmation('Coming now'),
      ]) {
        expect(copy.contains('\u2014'), isFalse);
        expect(copy.contains('\u2013'), isFalse);
      }
    });
  });
}


/// Reduced motion (audit design principle 3: "every animation must check reduced
/// motion"). A CircularProgressIndicator is the one animation Flutter does not
/// stop on its own, so the speaking state substitutes a static marker. Nothing is
/// lost: the live region already announces the state in words.
void _reducedMotionGroup() {
  group('The speaking spinner respects reduced motion', () {
    Widget host(ReplyController c, {required bool disableAnimations}) => MaterialApp(
          theme: ThresholdTheme.dark(),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: disableAnimations),
              child: Scaffold(
                body: ReplyBar(controller: c, contextualSuggestions: const <String>[]),
              ),
            ),
          ),
        );

    testWidgets('a static marker replaces the spinner when animations are off',
        (tester) async {
      final port = _BlockingReplyPort();
      final c = ReplyController(port: port, outbound: _twoWay());
      await tester.pumpWidget(host(c, disableAnimations: true));
      await tester.pump();
      final sending = c.send('Coming now', source: ReplySource.template);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(kSpeakingStaticIcon), findsOneWidget);
      // The state is still announced, which is what actually carries the meaning.
      expect(find.text(kSpeakingAtDoorLabel), findsOneWidget);
      port.finish(SpeakOutcome.spoken);
      await sending;
      await tester.pumpAndSettle();
      c.dispose();
    });

    testWidgets('the spinner is used normally', (tester) async {
      final port = _BlockingReplyPort();
      final c = ReplyController(port: port, outbound: _twoWay());
      await tester.pumpWidget(host(c, disableAnimations: false));
      await tester.pump();
      final sending = c.send('Coming now', source: ReplySource.template);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(kSpeakingStaticIcon), findsNothing);
      port.finish(SpeakOutcome.spoken);
      await sending;
      await tester.pumpAndSettle();
      c.dispose();
    });
  });
}
