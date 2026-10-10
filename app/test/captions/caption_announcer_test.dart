// LOW-09: each newly finalized caption turn is announced once, throttled, so a
// screen reader is not flooded and does not re-read the whole run on every
// partial update.

import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/captions/caption_announcer.dart';
import 'package:threshold/captions/turn_segmentation.dart';

CaptionTurn turn(String text, {bool isFinal = true, CaptionSpeaker speaker = CaptionSpeaker.visitor}) =>
    CaptionTurn(
      speaker: speaker,
      text: text,
      isFinal: isFinal,
      startedAtMs: 0,
      lastUpdatedMs: 0,
      provisional: !isFinal,
    );

void main() {
  group('CaptionAnnouncer (LOW-09)', () {
    test('announces a newly finalized turn once', () {
      var now = 0;
      final a = CaptionAnnouncer(nowMs: () => now, minGapMs: 100);
      final msg = a.announcementFor(<CaptionTurn>[turn('hello there')]);
      expect(msg, 'Visitor said: hello there');
      // The same turn is not announced again.
      now += 1000;
      expect(a.announcementFor(<CaptionTurn>[turn('hello there')]), isNull);
    });

    test('does not announce a provisional turn', () {
      final a = CaptionAnnouncer(nowMs: () => 0);
      expect(a.announcementFor(<CaptionTurn>[turn('typing', isFinal: false)]), isNull);
    });

    test('throttles a burst: within the gap nothing new is announced', () {
      var now = 0;
      final a = CaptionAnnouncer(nowMs: () => now, minGapMs: 500);
      expect(a.announcementFor(<CaptionTurn>[turn('one')]), 'Visitor said: one');
      now += 100; // inside the throttle window
      // A second finalized turn arrives but is suppressed by the throttle.
      expect(a.announcementFor(<CaptionTurn>[turn('one'), turn('two')]), isNull);
      now += 500; // window elapsed
      // Now the latest finalized turn is announced (only the newest).
      expect(a.announcementFor(<CaptionTurn>[turn('one'), turn('two')]), 'Visitor said: two');
    });

    test('labels the resident turn as "You"', () {
      final a = CaptionAnnouncer(nowMs: () => 0);
      expect(
        a.announcementFor(<CaptionTurn>[turn('on my way', speaker: CaptionSpeaker.resident)]),
        'You said: on my way',
      );
    });

    test('reset re-announces after a new session starts', () {
      var now = 0;
      final a = CaptionAnnouncer(nowMs: () => now, minGapMs: 0);
      expect(a.announcementFor(<CaptionTurn>[turn('hi')]), isNotNull);
      a.reset();
      now += 1;
      expect(a.announcementFor(<CaptionTurn>[turn('hi')]), isNotNull);
    });
  });
}
