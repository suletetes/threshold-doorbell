import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/connectivity/connectivity_port.dart';
import 'package:threshold/connectivity/connectivity_state.dart';
import 'package:threshold/connectivity/connectivity_controller.dart';

void main() {
  group('ConnectivityController (Task 22, FR-15.1..15.4; AT-17, AT-20)', () {
    test('starts in the state derived from the initial signal', () {
      final port = FixtureConnectivity();
      final c = ConnectivityController(port);
      expect(c.state, ConnectivityState.online);
      expect(c.isOnline, isTrue);
      expect(c.canOpenSession, isTrue);
      c.dispose();
    });

    test(
        'going offline blocks sessions but keeps cached history (FR-15.1, 15.2; AT-17)',
        () async {
      final port = FixtureConnectivity();
      final c = ConnectivityController(port);
      var notified = 0;
      c.addListener(() => notified++);

      port.goOffline();
      await Future<void>.delayed(Duration.zero);

      expect(c.isOffline, isTrue);
      expect(c.canOpenSession, isFalse);
      expect(c.canReadCachedHistory, isTrue);
      expect(c.availability(NetworkAction.openSession).reason,
          UnavailableReason.offline);
      expect(notified, 1);
      c.dispose();
    });

    test('backend unreachable is distinct from offline (FR-15.4; AT-20)',
        () async {
      final port = FixtureConnectivity();
      final c = ConnectivityController(port);
      port.goBackendUnreachable();
      await Future<void>.delayed(Duration.zero);

      expect(c.isBackendUnreachable, isTrue);
      expect(c.isOffline, isFalse);
      expect(c.canOpenSession, isFalse);
      expect(c.canReadCachedHistory, isTrue);
      expect(
        c.availability(NetworkAction.openSession).reason,
        UnavailableReason.backendUnreachable,
      );
      c.dispose();
    });

    test(
        'auto-restores online when connectivity returns, no restart (FR-15.3; AT-17)',
        () async {
      final port = FixtureConnectivity(
        initial: const ConnectivitySignal(
            hasNetwork: false, backendReachable: false),
      );
      final c = ConnectivityController(port);
      expect(c.isOffline, isTrue);

      port.goOnline();
      await Future<void>.delayed(Duration.zero);

      expect(c.isOnline, isTrue);
      expect(c.canOpenSession, isTrue);
      c.dispose();
    });

    test(
        'transitions offline -> backend-unreachable -> online each notify once',
        () async {
      final port = FixtureConnectivity(
        initial: const ConnectivitySignal(
            hasNetwork: false, backendReachable: false),
      );
      final c = ConnectivityController(port);
      final states = <ConnectivityState>[];
      c.addListener(() => states.add(c.state));

      port.goBackendUnreachable();
      await Future<void>.delayed(Duration.zero);
      port.goOnline();
      await Future<void>.delayed(Duration.zero);

      expect(states, [
        ConnectivityState.backendUnreachableOnline,
        ConnectivityState.online,
      ]);
      c.dispose();
    });

    test('an identical repeated signal does not churn listeners', () async {
      final port = FixtureConnectivity();
      final c = ConnectivityController(port);
      var notified = 0;
      c.addListener(() => notified++);

      port.goOnline(); // already online -> same state
      await Future<void>.delayed(Duration.zero);
      port.goOnline();
      await Future<void>.delayed(Duration.zero);

      expect(notified, 0);
      c.dispose();
    });
  });
}
