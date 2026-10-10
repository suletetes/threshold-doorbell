// HIGH-03 regression (probe P10). replyControllerProvider used to watch the
// sessionControllerProvider ChangeNotifierProvider directly, so every
// notifyListeners() (a caption, a reconnect, a haptic tick) re-ran the builder
// and disposed the reply controller mid-send, throwing "A ReplyController was
// used after being disposed." These tests pin that a session notify does NOT
// replace or dispose the reply controller while a reply is in flight.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/app/providers.dart';
import 'package:threshold/captions/turn_segmentation.dart';
import 'package:threshold/reply/reply_controller.dart';
import 'package:threshold/reply/reply_port.dart';
import 'package:threshold/reply/suggestion_provider.dart';
import 'package:threshold/session/ring_app_launcher.dart';
import 'package:threshold/session/session_port.dart';
import 'package:threshold/settings/settings_controller.dart';

ProviderContainer _container(FakeSessionPort port) {
  final container = ProviderContainer(
    overrides: <Override>[
      sessionPortProvider.overrideWithValue(port),
      replyPortProvider.overrideWithValue(FakeReplyPort()),
      ringAppLauncherProvider.overrideWithValue(FakeRingAppLauncher()),
      bedrockSuggestionPortProvider.overrideWithValue(FakeBedrockSuggestionPort()),
      dataErasurePortProvider.overrideWithValue(FakeDataErasurePort()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('replyControllerProvider stability (HIGH-03, probe P10)', () {
    test('a session notify does not replace the reply controller', () async {
      final port = FakeSessionPort();
      final container = _container(port);

      final session = container.read(sessionControllerProvider.notifier);
      await session.open(deviceId: 'dev-1');

      final first = container.read(replyControllerProvider.notifier);

      // A caption tick (session notifyListeners) used to rebuild this provider.
      session.ingestCaption(
        const CaptionResult(
          speaker: CaptionSpeaker.visitor,
          text: 'hello',
          isFinal: false,
          timestampMs: 0,
        ),
      );
      // And so did a reconnect / haptic tick.
      session.onIncomingEvent(eventDeviceId: 'dev-1', eventType: 'ring');

      final second = container.read(replyControllerProvider.notifier);
      expect(identical(first, second), isTrue,
          reason: 'the reply controller must survive a session notify');
    });

    test('a reply in flight is not disposed by a caption tick', () async {
      final port = FakeSessionPort();
      final container = _container(port);
      final session = container.read(sessionControllerProvider.notifier);
      await session.open(deviceId: 'dev-1');

      final reply = container.read(replyControllerProvider.notifier);

      // Start a reply. Fire a session caption tick while it is in flight, then
      // let the send finish. Before the fix this threw a FlutterError because
      // the provider rebuilt and disposed `reply` mid-send.
      final sending = reply.send('on my way', source: ReplySource.template);
      session.ingestCaption(
        const CaptionResult(
          speaker: CaptionSpeaker.visitor,
          text: 'who is it',
          isFinal: false,
          timestampMs: 10,
        ),
      );
      await sending;

      // The same controller is still live and completed the send.
      expect(container.read(replyControllerProvider.notifier), same(reply));
      expect(reply.turns.length, 1);
      expect(reply.turns.single.text, 'on my way');
    });
  });
}
