// Connectivity controller (Task 22, FR-15.1..15.4; AT-17, AT-20). Observes a
// ConnectivityPort, exposes the current ConnectivityState, and answers whether a
// given NetworkAction is allowed right now (FR-15.2). It auto-restores online
// capability when connectivity returns, without any app restart (FR-15.3), by
// simply reducing each incoming signal to the new state. It is a
// ChangeNotifier so a Riverpod provider can rebuild the UI on change; the
// reduction itself is the pure logic in connectivity_state.dart.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'connectivity_port.dart';
import 'connectivity_state.dart';

class ConnectivityController extends ChangeNotifier {
  ConnectivityController(this._port) {
    _state = stateFromSignal(_port.current);
    _sub = _port.signals.listen(_onSignal);
  }

  final ConnectivityPort _port;
  late StreamSubscription<ConnectivitySignal> _sub;
  late ConnectivityState _state;

  ConnectivityState get state => _state;

  bool get isOnline => _state == ConnectivityState.online;
  bool get isOffline => _state == ConnectivityState.offline;
  bool get isBackendUnreachable => _state == ConnectivityState.backendUnreachableOnline;

  /// Whether cached transcript history is usable. True in every state
  /// (FR-15.1, 15.4): history never depends on the network.
  bool get canReadCachedHistory =>
      availabilityOf(NetworkAction.readCachedHistory, _state).allowed;

  /// Whether a live session can be opened right now (FR-15.4). Requires the
  /// backend for signaling, so it is blocked offline and when the backend is
  /// unreachable.
  bool get canOpenSession => availabilityOf(NetworkAction.openSession, _state).allowed;

  /// Availability of an arbitrary network action, with a reason when blocked.
  ActionAvailability availability(NetworkAction action) => availabilityOf(action, _state);

  void _onSignal(ConnectivitySignal signal) {
    final next = stateFromSignal(signal);
    if (next == _state) return; // no churn on identical state
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
