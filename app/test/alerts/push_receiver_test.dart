import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/alerts/haptic_vocabulary.dart';
import 'package:threshold/alerts/push_receiver.dart';

void main() {
  group('Alert dispatch (FR-3.3, FR-3.4)', () {
    test('maps a person_detected push to the person haptic and thumbnail', () {
      final alert = PushAlert.fromMap({
        'type': 'person_detected',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'deviceId': 'd1',
        'thumbnailUrl': 'https://example/thumb.jpg',
      });
      final dispatch = dispatchForAlert(alert);
      expect(dispatch.haptic, HapticEvent.personAtDoor);
      expect(dispatch.thumbnailUrl, 'https://example/thumb.jpg');
      expect(dispatch.isKnownEvent, isTrue);
    });

    test('maps motion_detected to the motion haptic', () {
      final alert = PushAlert.fromMap({'type': 'motion_detected', 'deviceId': 'd1'});
      expect(dispatchForAlert(alert).haptic, HapticEvent.motion);
    });

    test('an unknown event type yields a null haptic without crashing (drift)', () {
      final alert = PushAlert.fromMap({'type': 'nonsense', 'deviceId': 'd1'});
      final dispatch = dispatchForAlert(alert);
      expect(dispatch.haptic, isNull);
      expect(dispatch.isKnownEvent, isFalse);
    });

    test('handles a missing thumbnail gracefully', () {
      final alert = PushAlert.fromMap({'type': 'person_detected', 'deviceId': 'd1'});
      expect(dispatchForAlert(alert).thumbnailUrl, isNull);
    });
  });

  group('FixturePushReceiver (FR-3.5 poll fallback)', () {
    test('delivers when push is available', () {
      final receiver = FixturePushReceiver();
      final ok = receiver.deliver(
        const PushAlert(type: 'person_detected', timestamp: '', deviceId: 'd1', thumbnailUrl: null),
      );
      expect(ok, isTrue);
      expect(receiver.delivered, hasLength(1));
    });

    test('returns false (not a silent drop) when push is unavailable', () {
      final receiver = FixturePushReceiver(pushAvailable: false);
      final ok = receiver.deliver(
        const PushAlert(type: 'motion_detected', timestamp: '', deviceId: 'd1', thumbnailUrl: null),
      );
      // Caller must fall back to the foreground poll (FR-3.5).
      expect(ok, isFalse);
      expect(receiver.isPushAvailable, isFalse);
      expect(receiver.delivered, isEmpty);
    });

    test('push availability can be toggled at runtime (permission change)', () {
      final receiver = FixturePushReceiver(pushAvailable: false);
      expect(receiver.isPushAvailable, isFalse);
      receiver.pushAvailable = true;
      expect(receiver.isPushAvailable, isTrue);
    });
  });
}
