// Connectivity source port and fixture (Task 22, FR-15.1..15.4; AT-17, AT-20).
// The live binding wraps connectivity_plus (network changes) plus a periodic
// backend health probe; both are device/network bound and deferred to the
// developer's machine. The fixture drives ConnectivitySignal changes so the
// ConnectivityController's gating and auto-restore behavior is unit-testable.

import 'dart:async';
import 'connectivity_state.dart';

/// Source of connectivity signals. The controller subscribes and derives state.
abstract class ConnectivityPort {
  /// The most recent known signal (for a synchronous initial read).
  ConnectivitySignal get current;

  /// Stream of signal changes (network up/down, backend reachable/unreachable).
  Stream<ConnectivitySignal> get signals;
}

/// Deterministic fixture: tests push signals to drive state transitions.
class FixtureConnectivity implements ConnectivityPort {
  FixtureConnectivity({
    ConnectivitySignal initial = const ConnectivitySignal(hasNetwork: true, backendReachable: true),
  }) : _current = initial;

  ConnectivitySignal _current;
  final StreamController<ConnectivitySignal> _controller =
      StreamController<ConnectivitySignal>.broadcast();

  @override
  ConnectivitySignal get current => _current;

  @override
  Stream<ConnectivitySignal> get signals => _controller.stream;

  /// Emit a new signal. Deduplicated so an identical signal does not churn.
  void emit(ConnectivitySignal signal) {
    _current = signal;
    _controller.add(signal);
  }

  /// Convenience: go fully offline (FR-15.1, 15.2).
  void goOffline() => emit(const ConnectivitySignal(hasNetwork: false, backendReachable: false));

  /// Convenience: online with backend reachable (FR-15.3 restore).
  void goOnline() => emit(const ConnectivitySignal(hasNetwork: true, backendReachable: true));

  /// Convenience: network up but backend unreachable (FR-15.4).
  void goBackendUnreachable() =>
      emit(const ConnectivitySignal(hasNetwork: true, backendReachable: false));

  Future<void> dispose() => _controller.close();
}
