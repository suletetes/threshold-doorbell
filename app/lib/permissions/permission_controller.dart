// Permission controller (Task 20, FR-13.1..FR-13.5; AT-13). Coordinates the
// in-context request flow: show a plain-language rationale immediately before
// first use (FR-13.2), request via the PermissionPort, keep unaffected features
// usable on denial (FR-13.3), show a one-tap OS-settings deep link on permanent
// denial without re-prompting (FR-13.4), and fall back to the foreground poll
// when notifications are denied (FR-13.5). A ChangeNotifier so the UI updates.

import 'package:flutter/foundation.dart';

import 'permission_port.dart';

/// What the UI should do for a permission after a request or a status check.
enum PermissionUiState {
  /// Not yet requested: show the in-context rationale before requesting (FR-13.2).
  needsRationale,

  /// Granted: the dependent feature is fully available.
  granted,

  /// Denied this time: the feature is unavailable but the app is not blocked
  /// (FR-13.3); the resident may be asked again later.
  deniedRetryable,

  /// Permanently denied: show the OS-settings deep link, do not re-prompt
  /// (FR-13.4).
  needsSettings,
}

/// Plain-language rationale strings shown before each request (FR-13.2).
/// Dash-free (NFR-10).
String rationaleFor(AppPermission permission) {
  switch (permission) {
    case AppPermission.notifications:
      return 'Threshold uses notifications to alert you the moment someone is at '
          'your door, with a vibration you can feel.';
    case AppPermission.microphone:
      return 'Threshold needs the microphone so it can open a two way audio '
          'channel to your doorbell. Your voice is not recorded; replies are '
          'spoken by a synthesized voice.';
  }
}

/// A short explanation of what is unavailable when a permission is denied
/// (FR-13.3, FR-13.5). Dash-free (NFR-10).
String unavailableExplanationFor(AppPermission permission) {
  switch (permission) {
    case AppPermission.notifications:
      return 'Live alerts are unavailable until you enable notifications. You '
          'will still see recent events when you open the app.';
    case AppPermission.microphone:
      return 'Spoken replies are unavailable until you enable the microphone. '
          'You can still see live captions of your visitor.';
  }
}

class PermissionController extends ChangeNotifier {
  PermissionController(this._port);

  final PermissionPort _port;

  final Map<AppPermission, PermissionStatus> _statuses =
      <AppPermission, PermissionStatus>{};

  /// Whether the app should fall back to the foreground poll for events because
  /// notifications are unavailable (FR-13.5). True when notifications are denied
  /// or permanently denied.
  bool get pollFallbackActive {
    final s = _statuses[AppPermission.notifications];
    return s == PermissionStatus.denied ||
        s == PermissionStatus.permanentlyDenied;
  }

  PermissionStatus statusOf(AppPermission permission) =>
      _statuses[permission] ?? PermissionStatus.notDetermined;

  /// The UI state for a permission given its current status.
  PermissionUiState uiStateOf(AppPermission permission) =>
      _uiState(statusOf(permission));

  PermissionUiState _uiState(PermissionStatus status) {
    switch (status) {
      case PermissionStatus.notDetermined:
        return PermissionUiState.needsRationale;
      case PermissionStatus.granted:
        return PermissionUiState.granted;
      case PermissionStatus.denied:
        return PermissionUiState.deniedRetryable;
      case PermissionStatus.permanentlyDenied:
        return PermissionUiState.needsSettings;
    }
  }

  /// Refresh the cached status of [permission] without prompting.
  Future<PermissionUiState> refresh(AppPermission permission) async {
    final s = await _port.status(permission);
    _statuses[permission] = s;
    notifyListeners();
    return _uiState(s);
  }

  /// Request [permission] after the rationale was shown (FR-13.2). If the
  /// permission is already permanently denied, this does NOT re-prompt
  /// (FR-13.4); the caller should route to settings instead. Returns the
  /// resulting UI state.
  Future<PermissionUiState> request(AppPermission permission) async {
    final current = statusOf(permission);
    if (current == PermissionStatus.permanentlyDenied) {
      // Do not re-prompt repeatedly (FR-13.4).
      return PermissionUiState.needsSettings;
    }
    final result = await _port.request(permission);
    _statuses[permission] = result;
    notifyListeners();
    return _uiState(result);
  }

  /// Open OS settings for a permanently denied permission (FR-13.4), then
  /// refresh the cached status when the resident returns (LOW-07). The old code
  /// opened settings but never re-checked, so a permission the resident just
  /// granted in Settings still showed as denied until something else refreshed
  /// it. Returns whether settings opened. Pass [permission] to refresh a single
  /// permission; with none, every tracked permission is refreshed.
  Future<bool> openSettings([AppPermission? permission]) async {
    final opened = await _port.openSettings();
    // Re-read status on return from the OS settings screen so a change the
    // resident made there is reflected immediately (LOW-07).
    if (permission != null) {
      await refresh(permission);
    } else {
      final tracked = _statuses.keys.toList();
      for (final p in tracked) {
        await refresh(p);
      }
    }
    return opened;
  }
}
