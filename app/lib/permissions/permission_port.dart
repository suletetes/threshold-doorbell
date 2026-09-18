// Permission port (Task 20, FR-13.1..FR-13.5; AT-13). The app requests only
// notifications and microphone (microphone is required by the WebRTC runtime to
// negotiate a sendrecv audio track). Camera is NEVER requested: the outbound
// track is synthesized, not captured (FR-13.1). permission_handler is
// device-bound, so it sits behind this interface with a fake for headless tests.
// The live binding maps permission_handler statuses onto PermissionStatus and
// openAppSettings onto [openSettings].

import 'dart:async';

/// The permissions the app may request. Camera is intentionally absent (FR-13.1):
/// requesting it is a bug the type system prevents.
enum AppPermission {
  /// Push notifications for door events (FR-3.3, FR-13.5).
  notifications,

  /// Microphone, required by the WebRTC runtime for a sendrecv audio track
  /// (FR-13.1). Not used to capture the resident's voice for the reply, which is
  /// synthesized.
  microphone,
}

/// Normalized permission status (mirrors permission_handler's PermissionStatus).
enum PermissionStatus {
  /// Not yet requested.
  notDetermined,

  /// Granted.
  granted,

  /// Denied this time, but can be requested again (FR-13.3).
  denied,

  /// Permanently denied: must be enabled from OS settings (FR-13.4).
  permanentlyDenied,
}

/// The device permission binding. The live implementation wraps
/// permission_handler; the fake scripts statuses for tests.
abstract class PermissionPort {
  /// Current status of [permission] without prompting.
  Future<PermissionStatus> status(AppPermission permission);

  /// Request [permission] in-context (FR-13.2). Returns the resulting status.
  Future<PermissionStatus> request(AppPermission permission);

  /// Open the OS app-settings page so the resident can enable a permanently
  /// denied permission (FR-13.4). Returns true if settings could be opened.
  Future<bool> openSettings();
}

/// Deterministic fake. Tests script the result of the next request per
/// permission and can assert that camera is never requested (there is no camera
/// value, so it cannot be) and that settings deep link is used at most once.
class FakePermissionPort implements PermissionPort {
  FakePermissionPort({
    Map<AppPermission, PermissionStatus>? initial,
    Map<AppPermission, PermissionStatus>? requestResults,
    this.canOpenSettings = true,
  })  : _status = Map<AppPermission, PermissionStatus>.from(
          initial ??
              <AppPermission, PermissionStatus>{
                AppPermission.notifications: PermissionStatus.notDetermined,
                AppPermission.microphone: PermissionStatus.notDetermined,
              },
        ),
        _requestResults = Map<AppPermission, PermissionStatus>.from(
          requestResults ?? const <AppPermission, PermissionStatus>{},
        );

  final Map<AppPermission, PermissionStatus> _status;
  final Map<AppPermission, PermissionStatus> _requestResults;
  final bool canOpenSettings;

  final List<AppPermission> requestedPermissions = <AppPermission>[];
  int openSettingsCalls = 0;

  @override
  Future<PermissionStatus> status(AppPermission permission) async =>
      _status[permission] ?? PermissionStatus.notDetermined;

  @override
  Future<PermissionStatus> request(AppPermission permission) async {
    requestedPermissions.add(permission);
    final result = _requestResults[permission] ?? PermissionStatus.granted;
    _status[permission] = result;
    return result;
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCalls++;
    return canOpenSettings;
  }
}
