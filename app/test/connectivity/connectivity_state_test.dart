import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/connectivity/connectivity_state.dart';

void main() {
  group('stateFromSignal (Task 22, FR-15.4)', () {
    test('network + backend reachable is online', () {
      final s = stateFromSignal(
        const ConnectivitySignal(hasNetwork: true, backendReachable: true),
      );
      expect(s, ConnectivityState.online);
    });

    test('no network is offline regardless of backend flag', () {
      expect(
        stateFromSignal(const ConnectivitySignal(hasNetwork: false, backendReachable: false)),
        ConnectivityState.offline,
      );
      // Even if a stale backendReachable=true lingers, no network means offline.
      expect(
        stateFromSignal(const ConnectivitySignal(hasNetwork: false, backendReachable: true)),
        ConnectivityState.offline,
      );
    });

    test('network but backend unreachable is a distinct state (FR-15.4)', () {
      final s = stateFromSignal(
        const ConnectivitySignal(hasNetwork: true, backendReachable: false),
      );
      expect(s, ConnectivityState.backendUnreachableOnline);
      expect(s, isNot(ConnectivityState.offline));
    });
  });

  group('availabilityOf (Task 22, FR-15.1, 15.2, 15.4)', () {
    test('reading cached history is allowed in every state (FR-15.1, 15.4)', () {
      for (final state in ConnectivityState.values) {
        expect(availabilityOf(NetworkAction.readCachedHistory, state).allowed, isTrue);
      }
    });

    test('online allows every action', () {
      for (final action in NetworkAction.values) {
        expect(availabilityOf(action, ConnectivityState.online).allowed, isTrue);
      }
    });

    test('offline blocks remote actions with the offline reason (FR-15.2)', () {
      final a = availabilityOf(NetworkAction.openSession, ConnectivityState.offline);
      expect(a.allowed, isFalse);
      expect(a.reason, UnavailableReason.offline);
      expect(availabilityOf(NetworkAction.linkAccount, ConnectivityState.offline).allowed, isFalse);
      expect(availabilityOf(NetworkAction.fetchRemote, ConnectivityState.offline).allowed, isFalse);
    });

    test('backend-unreachable blocks live sessions with the backend reason (FR-15.4)', () {
      final a = availabilityOf(
        NetworkAction.openSession,
        ConnectivityState.backendUnreachableOnline,
      );
      expect(a.allowed, isFalse);
      expect(a.reason, UnavailableReason.backendUnreachable);
    });

    test('backend-unreachable still allows cached history (FR-15.4)', () {
      expect(
        availabilityOf(
          NetworkAction.readCachedHistory,
          ConnectivityState.backendUnreachableOnline,
        ).allowed,
        isTrue,
      );
    });

    test('the two blocked reasons are distinct so the UI can explain each', () {
      final offline = availabilityOf(NetworkAction.fetchRemote, ConnectivityState.offline).reason;
      final backend = availabilityOf(
        NetworkAction.fetchRemote,
        ConnectivityState.backendUnreachableOnline,
      ).reason;
      expect(offline, isNot(backend));
    });
  });
}
