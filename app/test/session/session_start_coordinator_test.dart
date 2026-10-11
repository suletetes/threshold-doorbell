// P2-4: the session-start flow consults ModelProvisioningMachine (FR-5.2a) and
// RecordingNoticeController.resolveSessionStart (FR-14.3a).

import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/captions/model_provisioning.dart';
import 'package:threshold/consent/recording_notice.dart';
import 'package:threshold/consent/recording_notice_controller.dart';
import 'package:threshold/session/session_start_coordinator.dart';
import 'package:threshold/session/session_state.dart';

ModelProvisioningMachine _notReady() =>
    ModelProvisioningMachine(modelSizeBytes: 1000);

ModelProvisioningMachine _verified() {
  final m = ModelProvisioningMachine(modelSizeBytes: 1000);
  m.optIn();
  m.startDownload(liveSessionActive: false);
  m.onDownloadComplete();
  m.onVerified(ok: true);
  return m;
}

Future<RecordingNoticeController> _notice({
  bool audible = false,
  ComplianceChoice? defaultChoice,
}) async {
  final c = RecordingNoticeController(
    FakeConsentStore(
        acknowledged: true,
        audibleNotice: audible,
        defaultChoice: defaultChoice),
  );
  await c.load();
  return c;
}

void main() {
  group('Privacy-Mode model gating (P2-4, FR-5.2a, AT-21)', () {
    test('Privacy Mode is refused and labelled until the model verifies',
        () async {
      final coord = SessionStartCoordinator(
        provisioning: _notReady(),
        recordingNotice: await _notice(),
      );
      expect(coord.privacyModeAvailable, isFalse);
      final plan = coord.resolve(
        requestedMode: SessionCaptionMode.privacy,
        outboundAvailable: true,
      );
      // Privacy refused; falls back to Clarity with a dash-free label.
      expect(plan.privacyRefused, isTrue);
      expect(plan.mode, SessionCaptionMode.clarity);
      expect(plan.privacyUnavailableLabel, isNotEmpty);
      expect(plan.privacyUnavailableLabel.contains('\u2014'), isFalse);
    });

    test('Privacy Mode is allowed once the model is verified', () async {
      final coord = SessionStartCoordinator(
        provisioning: _verified(),
        recordingNotice: await _notice(),
      );
      expect(coord.privacyModeAvailable, isTrue);
      final plan = coord.resolve(
        requestedMode: SessionCaptionMode.privacy,
        outboundAvailable: true,
      );
      expect(plan.privacyRefused, isFalse);
      expect(plan.mode, SessionCaptionMode.privacy);
    });
  });

  group('Recording-notice fallback at session start (P2-4, FR-14.3a, AT-14)',
      () {
    test('audible notice enabled + outbound unavailable + no default => prompt',
        () async {
      final coord = SessionStartCoordinator(
        provisioning: _verified(),
        recordingNotice: await _notice(audible: true),
      );
      final plan = coord.resolve(
        requestedMode: SessionCaptionMode.clarity,
        outboundAvailable: false,
      );
      expect(plan.noticeAction, SessionNoticeAction.promptComplianceFallback);
      expect(plan.mustPromptComplianceFallback, isTrue);
    });

    test('branch: remembered continue-without-notice is honored', () async {
      final coord = SessionStartCoordinator(
        provisioning: _verified(),
        recordingNotice: await _notice(
          audible: true,
          defaultChoice: ComplianceChoice.continueWithoutNotice,
        ),
      );
      final plan = coord.resolve(
        requestedMode: SessionCaptionMode.clarity,
        outboundAvailable: false,
      );
      expect(plan.noticeAction, SessionNoticeAction.continueWithoutNotice);
      expect(plan.transcriptionDisabled, isFalse);
    });

    test('branch: remembered disable-transcription is honored', () async {
      final coord = SessionStartCoordinator(
        provisioning: _verified(),
        recordingNotice: await _notice(
          audible: true,
          defaultChoice: ComplianceChoice.disableTranscription,
        ),
      );
      final plan = coord.resolve(
        requestedMode: SessionCaptionMode.clarity,
        outboundAvailable: false,
      );
      expect(plan.noticeAction, SessionNoticeAction.disableTranscription);
      expect(plan.transcriptionDisabled, isTrue);
    });

    test('audible notice enabled + outbound available => play then transcribe',
        () async {
      final coord = SessionStartCoordinator(
        provisioning: _verified(),
        recordingNotice: await _notice(audible: true),
      );
      final plan = coord.resolve(
        requestedMode: SessionCaptionMode.clarity,
        outboundAvailable: true,
      );
      expect(plan.noticeAction, SessionNoticeAction.playAudibleThenTranscribe);
    });

    test('no audible notice => transcribe with no notice', () async {
      final coord = SessionStartCoordinator(
        provisioning: _verified(),
        recordingNotice: await _notice(audible: false),
      );
      final plan = coord.resolve(
        requestedMode: SessionCaptionMode.clarity,
        outboundAvailable: false,
      );
      expect(plan.noticeAction, SessionNoticeAction.transcribeNoNotice);
    });
  });
}
