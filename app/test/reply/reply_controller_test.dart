import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/reply/echo_gate.dart';
import 'package:threshold/reply/outbound_mode.dart';
import 'package:threshold/reply/reply_controller.dart';
import 'package:threshold/reply/reply_port.dart';
import 'package:threshold/reply/reply_suggestions.dart';
import 'package:threshold/reply/ondevice_suggestions.dart';

OutboundModeMachine _twoWay() => OutboundModeMachine()..applyProbe(ProbeResult.success);

void main() {
  group('ReplyController lifecycle (Task 15, FR-6.1, 6.3, 6.5, G3; AT-5)', () {
    test('a successful reply speaks, appends a resident turn, and reaches SENT', () async {
      final port = FakeReplyPort();
      final c = ReplyController(port: port, outbound: _twoWay(), nowMs: () => 42);
      await c.send('Please leave it at the door', source: ReplySource.template);
      expect(port.speakCalls, 1);
      expect(port.spokenTexts.single, 'Please leave it at the door');
      expect(c.state, ReplyState.sent);
      expect(c.turns.length, 1);
      expect(c.turns.single.text, 'Please leave it at the door');
      expect(c.turns.single.source, ReplySource.template);
      expect(c.turns.single.atMs, 42);
    });

    test('the echo gate closes while speaking and records a gap (FR-5.6 wiring)', () async {
      var now = 0;
      final gate = EchoGate(nowMs: () => now);
      final port = FakeReplyPort();
      final c = ReplyController(port: port, outbound: _twoWay(), echoGate: gate, nowMs: () => now);
      await c.send('Hello', source: ReplySource.freetext);
      // Playback started+ended during send; advance past the 300 ms tail.
      now += kEchoTail.inMilliseconds;
      final gap = gate.settle();
      expect(gap, isNotNull);
      expect(gate.gaps.length, 1);
    });

    test('duplicate send is disabled while a reply is in flight (FR-6.3)', () async {
      // A never-completing speak keeps the controller in synthesizing.
      final port = _BlockingReplyPort();
      final c = ReplyController(port: port, outbound: _twoWay());
      final f = c.send('Hi', source: ReplySource.freetext);
      // While synthesizing, canSend is false and a second send is a no-op.
      expect(c.canSend('Hi'), isFalse);
      await c.send('Hi again', source: ReplySource.freetext);
      expect(port.speakCalls, 1); // the second send did not start
      port.complete(SpeakOutcome.spoken);
      await f;
      expect(c.state, ReplyState.sent);
    });

    test('TTS failure retries exactly once then succeeds', () async {
      final port = FakeReplyPort(plan: <SpeakOutcome>[SpeakOutcome.ttsFailed, SpeakOutcome.spoken]);
      final c = ReplyController(port: port, outbound: _twoWay());
      await c.send('Hi', source: ReplySource.freetext);
      expect(port.speakCalls, 2);
      expect(c.state, ReplyState.sent);
    });

    test('TTS failure twice ends in error with a dash-free message', () async {
      final port = FakeReplyPort(plan: <SpeakOutcome>[SpeakOutcome.ttsFailed, SpeakOutcome.ttsFailed]);
      final c = ReplyController(port: port, outbound: _twoWay());
      await c.send('Hi', source: ReplySource.freetext);
      expect(port.speakCalls, 2);
      expect(c.state, ReplyState.error);
      expect(c.turns, isEmpty); // nothing appended on failure
      expect(c.errorMessage!.contains('\u2014'), isFalse);
      expect(c.errorMessage!.contains('\u2013'), isFalse);
    });

    test('injection failure degrades the session to Captions-Only (FR-6.4b)', () async {
      final outbound = _twoWay();
      final port = FakeReplyPort(plan: <SpeakOutcome>[SpeakOutcome.injectionFailed]);
      final c = ReplyController(port: port, outbound: outbound);
      await c.send('Hi', source: ReplySource.freetext);
      expect(c.state, ReplyState.error);
      expect(outbound.isCaptionsOnly, isTrue);
      expect(outbound.outboundAvailable, isFalse);
      // Reply bar is now hidden (FR-6.4).
      expect(c.replyBarVisible, isFalse);
    });

    test('reply bar hidden and send blocked when outbound is unavailable (FR-6.4)', () async {
      final outbound = OutboundModeMachine()..applyProbe(ProbeResult.failure);
      final port = FakeReplyPort();
      final c = ReplyController(port: port, outbound: outbound);
      expect(c.replyBarVisible, isFalse);
      expect(c.canSend('Hi'), isFalse);
      await c.send('Hi', source: ReplySource.freetext);
      expect(port.speakCalls, 0); // nothing spoken
    });

    test('empty or whitespace text is never sent', () async {
      final port = FakeReplyPort();
      final c = ReplyController(port: port, outbound: _twoWay());
      await c.send('   ', source: ReplySource.freetext);
      expect(port.speakCalls, 0);
      expect(c.canSend(''), isFalse);
    });
  });

  group('composeReplyButtons (Task 15, FR-7.2, FR-7.5; AT-7)', () {
    test('always includes the fixed safe set even with no suggestions', () {
      final buttons = composeReplyButtons(const <String>[]);
      for (final safe in kFixedSafeReplies) {
        expect(buttons.contains(safe), isTrue);
      }
      expect(buttons, isNotEmpty); // never empty (FR-7.5)
    });

    test('caps contextual suggestions at 3 (FR-7.1)', () {
      final buttons = composeReplyButtons(const <String>['a', 'b', 'c', 'd', 'e']);
      // First three are the contextual ones, then the safe set.
      expect(buttons.take(3).toList(), <String>['a', 'b', 'c']);
      for (final safe in kFixedSafeReplies) {
        expect(buttons.contains(safe), isTrue);
      }
    });

    test('deduplicates a contextual suggestion equal to a safe reply', () {
      final buttons = composeReplyButtons(<String>['Please come back later']);
      final count = buttons.where((b) => b == 'Please come back later').length;
      expect(count, 1);
    });
  });
}

/// A ReplyPort whose speak() blocks until completed, to test the in-flight lock.
class _BlockingReplyPort implements ReplyPort {
  int speakCalls = 0;
  final _completers = <void Function(SpeakOutcome)>[];
  SpeakOutcome? _pending;

  @override
  Future<SpeakOutcome> speak(String text) async {
    speakCalls++;
    // Return a future that resolves when complete() is called.
    while (_pending == null) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    final out = _pending!;
    _pending = null;
    return out;
  }

  void complete(SpeakOutcome outcome) => _pending = outcome;
}
