// Connectivity state machine (Task 22, FR-15.1..15.4; AT-17, AT-20). Pure logic
// that gates network actions and distinguishes three conditions so the UI can
// show the right explanation and never fail silently (FR-15.2):
//
//   online                      - full capability.
//   offline                     - no network at all (FR-15.1, 15.2).
//   backendUnreachableOnline    - the device has connectivity but our backend is
//                                 not reachable; live sessions are unavailable
//                                 because signaling requires the backend
//                                 (FR-15.4, design.md §1 accepted single point of
//                                 failure), yet cached history stays usable.
//
// Cached transcripts remain readable and searchable in every state (FR-15.1,
// 15.4). Connectivity restore happens without an app restart (FR-15.3).
//
// The live connectivity source (connectivity_plus) and the backend reachability
// probe are device/network bound and deferred behind ConnectivityPort; this
// machine is driven by a fixture so the gating rules are exhaustively testable.

import 'package:flutter/foundation.dart';

/// The three connectivity conditions the app distinguishes (FR-15.4).
enum ConnectivityState {
  /// Network present and the backend is reachable: full capability.
  online,

  /// No network at all: only cached history and local features (FR-15.1).
  offline,

  /// Network present but the backend is unreachable: live sessions unavailable,
  /// cached history usable (FR-15.4).
  backendUnreachableOnline,
}

/// A network action the app may attempt. Used to decide whether the action is
/// allowed in the current state (FR-15.2) so the UI disables it with an
/// explanation rather than letting it fail silently.
enum NetworkAction {
  /// Open a live session. Requires the backend (signaling), so it is blocked
  /// whenever the backend is unreachable OR the device is offline (FR-15.4).
  openSession,

  /// Link a Ring account (OAuth). Requires network and the backend.
  linkAccount,

  /// Fetch fresh events/devices from the backend.
  fetchRemote,

  /// Read or search locally cached transcripts. Always allowed (FR-15.1, 15.4).
  readCachedHistory,
}

/// The reason a network action is unavailable, for a plain-language explanation
/// (FR-15.2). null when the action is allowed.
enum UnavailableReason {
  /// The device has no network connection.
  offline,

  /// The device is online but the backend cannot be reached (FR-15.4).
  backendUnreachable,
}

@immutable
class ActionAvailability {
  const ActionAvailability({required this.allowed, this.reason});

  final bool allowed;
  final UnavailableReason? reason;

  static const ActionAvailability ok = ActionAvailability(allowed: true);
}

/// Pure decision: is [action] allowed in [state], and if not, why (FR-15.2, 15.4).
ActionAvailability availabilityOf(NetworkAction action, ConnectivityState state) {
  // Reading cached history is always allowed, in every state (FR-15.1, 15.4).
  if (action == NetworkAction.readCachedHistory) {
    return ActionAvailability.ok;
  }
  switch (state) {
    case ConnectivityState.online:
      return ActionAvailability.ok;
    case ConnectivityState.offline:
      return const ActionAvailability(allowed: false, reason: UnavailableReason.offline);
    case ConnectivityState.backendUnreachableOnline:
      // Every remote action needs the backend, which is unreachable (FR-15.4).
      return const ActionAvailability(
        allowed: false,
        reason: UnavailableReason.backendUnreachable,
      );
  }
}

/// Raw signal from the connectivity source and the backend reachability probe.
@immutable
class ConnectivitySignal {
  const ConnectivitySignal({required this.hasNetwork, required this.backendReachable});

  /// Whether the device reports any network (wifi/cellular).
  final bool hasNetwork;

  /// Whether the backend health probe last succeeded. Only meaningful when
  /// [hasNetwork] is true; when offline the backend cannot be probed.
  final bool backendReachable;
}

/// Reduce a raw signal to the connectivity state (FR-15.4). When there is no
/// network the backend cannot be reached at all, so backend reachability is
/// ignored and the state is plain offline.
ConnectivityState stateFromSignal(ConnectivitySignal signal) {
  if (!signal.hasNetwork) return ConnectivityState.offline;
  return signal.backendReachable
      ? ConnectivityState.online
      : ConnectivityState.backendUnreachableOnline;
}
