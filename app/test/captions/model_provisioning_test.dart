import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/captions/model_provisioning.dart';

void main() {
  group('ModelProvisioningMachine (Task 18, FR-5.2a, FR-10.1; AT-21)', () {
    ModelProvisioningMachine make() =>
        ModelProvisioningMachine(modelSizeBytes: 40 * 1024 * 1024);

    test(
        'starts notPresent with Privacy Mode unavailable and labelled (FR-5.2a, AT-21)',
        () {
      final m = make();
      expect(m.state, ModelState.notPresent);
      expect(m.privacyModeAvailable, isFalse);
      expect(m.snapshot.unavailabilityLabel, isNotEmpty);
    });

    test('the model size is disclosed before download (FR-5.2a)', () {
      final m = make();
      expect(m.snapshot.sizeBytes, 40 * 1024 * 1024);
      m.optIn();
      expect(
          m.snapshot.sizeBytes, 40 * 1024 * 1024); // still disclosed at opt-in
    });

    test(
        'happy path: notPresent -> optIn -> downloading -> verifying -> verified enables Privacy Mode',
        () {
      final m = make();
      m.optIn();
      expect(m.state, ModelState.optIn);
      m.startDownload(liveSessionActive: false);
      expect(m.state, ModelState.downloading);
      m.onProgress(20 * 1024 * 1024);
      expect(m.snapshot.progress, closeTo(0.5, 0.001));
      m.onDownloadComplete();
      expect(m.state, ModelState.verifying);
      m.onVerified(ok: true);
      expect(m.state, ModelState.verified);
      expect(m.privacyModeAvailable, isTrue);
    });

    test('a download during a live session is refused (FR-5.2a)', () {
      final m = make();
      m.optIn();
      expect(
        () => m.startDownload(liveSessionActive: true),
        throwsA(isA<DownloadDuringSessionError>()),
      );
      // State is unchanged; still opt-in, still unavailable.
      expect(m.state, ModelState.optIn);
      expect(m.privacyModeAvailable, isFalse);
    });

    test(
        'a download without a prior opt-in is refused (explicit opt-in required, FR-5.2a)',
        () {
      final m = make();
      expect(() => m.startDownload(liveSessionActive: false), throwsStateError);
      expect(m.state, ModelState.notPresent);
    });

    test('Privacy Mode is unavailable in every non-verified state (FR-5.2a)',
        () {
      final m = make();
      expect(m.privacyModeAvailable, isFalse); // notPresent
      m.optIn();
      expect(m.privacyModeAvailable, isFalse); // optIn
      m.startDownload(liveSessionActive: false);
      expect(m.privacyModeAvailable, isFalse); // downloading
      m.onDownloadComplete();
      expect(m.privacyModeAvailable, isFalse); // verifying
    });

    test('verification failure keeps Privacy Mode unavailable and allows retry',
        () {
      final m = make();
      m.optIn();
      m.startDownload(liveSessionActive: false);
      m.onDownloadComplete();
      m.onVerified(ok: false);
      expect(m.state, ModelState.failed);
      expect(m.privacyModeAvailable, isFalse);
      // Retry via opt-in.
      m.optIn();
      expect(m.state, ModelState.optIn);
      m.startDownload(liveSessionActive: false);
      m.onDownloadComplete();
      m.onVerified(ok: true);
      expect(m.privacyModeAvailable, isTrue);
    });

    test('a download error transitions to failed and is retryable', () {
      final m = make();
      m.optIn();
      m.startDownload(liveSessionActive: false);
      m.onError();
      expect(m.state, ModelState.failed);
      m.optIn();
      expect(m.state, ModelState.optIn);
    });

    test('progress clamps into [0,1] and ignores out-of-state progress', () {
      final m = make();
      m.optIn();
      m.startDownload(liveSessionActive: false);
      m.onProgress(-100);
      expect(m.snapshot.progress, 0);
      m.onProgress(999 * 1024 * 1024);
      expect(m.snapshot.progress, 1);
      m.onDownloadComplete();
      m.onProgress(0); // ignored: not downloading anymore
      expect(m.snapshot.downloadedBytes, m.snapshot.sizeBytes);
    });

    test('labels never contain a forbidden dash (NFR-10)', () {
      final m = make();
      const forbidden = <String>['\u2014', '\u2013'];
      for (final state in ModelState.values) {
        // Reconstruct a snapshot in each state to read its label.
        final snap = m.snapshot.copyWith(state: state);
        for (final ch in forbidden) {
          expect(snap.unavailabilityLabel.contains(ch), isFalse);
        }
      }
    });
  });
}
