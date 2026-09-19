// Session-start coordinator (Task 18/21 wiring, FR-5.2a, FR-14.3, FR-14.3a;
// AT-14, AT-21). Consulted BEFORE a live session opens. It ties together the
// two decision machines the audit found unwired into any session flow:
//
//   * ModelProvisioningMachine (FR-5.2a): Privacy Mode is unavailable and
//     clearly labelled until the on-device model is present and verified. If the
//     resident requests Privacy Mode before the model is ready, the coordinator
//     refuses to start Privacy Mode and surfaces the unavailability label.
//   * RecordingNoticeController.resolveSessionStart (FR-14.3a): when the audible
//     door notice is enabled but outbound audio is unavailable, the session must
//     not silently transcribe; the resident is offered continue-without-notice
//     or disable-transcription (or a remembered default is honored).
//
// This is pure orchestration over the existing controllers/machines, so the
// gating is unit-testable without a device.

import '../consent/recording_notice.dart';
import '../consent/recording_notice_controller.dart';
import '../captions/model_provisioning.dart';
import 'session_state.dart';

/// What the caller should do about the recording notice at session start.
/// Mirrors [SessionNoticeAction] but is surfaced by the coordinator alongside
/// the mode decision so the UI has one result to act on.
typedef NoticeAction = SessionNoticeAction;

/// The resolved plan for starting a session.
class SessionStartPlan {
  const SessionStartPlan({
    required this.mode,
    required this.privacyRefused,
    required this.privacyUnavailableLabel,
    required this.noticeAction,
  });

  /// The mode the session should actually run. If Privacy was requested but the
  /// on-device model is not verified, this falls back to Clarity and
  /// [privacyRefused] is true (FR-5.2a).
  final SessionCaptionMode mode;

  /// True when Privacy Mode was requested but refused because the model is not
  /// yet verified (FR-5.2a).
  final bool privacyRefused;

  /// A dash-free label explaining why Privacy Mode is unavailable, when refused
  /// (FR-5.2a). Empty when Privacy was not refused.
  final String privacyUnavailableLabel;

  /// The recording-notice action for this session (FR-14.3a).
  final NoticeAction noticeAction;

  /// Whether transcription must be disabled for this session (FR-14.3a).
  bool get transcriptionDisabled =>
      noticeAction == SessionNoticeAction.disableTranscription;

  /// Whether the resident must be prompted for the compliance fallback before
  /// transcription may proceed (FR-14.3a).
  bool get mustPromptComplianceFallback =>
      noticeAction == SessionNoticeAction.promptComplianceFallback;
}

/// Coordinates the pre-session checks (FR-5.2a, FR-14.3a). Holds references to
/// the model-provisioning machine and the recording-notice controller; both are
/// consulted here so no session starts without honoring them.
class SessionStartCoordinator {
  SessionStartCoordinator({
    required ModelProvisioningMachine provisioning,
    required RecordingNoticeController recordingNotice,
  })  : _provisioning = provisioning,
        _recordingNotice = recordingNotice;

  final ModelProvisioningMachine _provisioning;
  final RecordingNoticeController _recordingNotice;

  /// Whether Privacy Mode can be selected right now (model verified, FR-5.2a).
  bool get privacyModeAvailable => _provisioning.privacyModeAvailable;

  /// The label to show when Privacy Mode is not yet usable (FR-5.2a).
  String get privacyUnavailableLabel => _provisioning.snapshot.unavailabilityLabel;

  /// Resolve how to start a session in the requested [mode] given the sticky
  /// [outboundAvailable] probe result. Consults the model-provisioning machine
  /// (Privacy gating, FR-5.2a) and the recording-notice controller (FR-14.3a).
  SessionStartPlan resolve({
    required SessionCaptionMode requestedMode,
    required bool outboundAvailable,
  }) {
    // Begin the notice session so any prior per-session choice is re-evaluated.
    _recordingNotice.beginSession();

    // FR-5.2a: Privacy Mode is unavailable until the model is verified. Refuse
    // Privacy and fall back to Clarity, surfacing the unavailability label.
    var mode = requestedMode;
    var privacyRefused = false;
    var label = '';
    if (requestedMode == SessionCaptionMode.privacy && !_provisioning.privacyModeAvailable) {
      mode = SessionCaptionMode.clarity;
      privacyRefused = true;
      label = _provisioning.snapshot.unavailabilityLabel;
    }

    // FR-14.3a: resolve the recording-notice action for this session.
    final notice = _recordingNotice.resolveSessionStart(
      outboundAvailable: outboundAvailable,
    );

    return SessionStartPlan(
      mode: mode,
      privacyRefused: privacyRefused,
      privacyUnavailableLabel: label,
      noticeAction: notice,
    );
  }
}
