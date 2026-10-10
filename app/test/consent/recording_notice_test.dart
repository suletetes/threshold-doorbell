import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/consent/recording_notice.dart';
import 'package:threshold/consent/recording_notice_controller.dart';

void main() {
  group('First-run acknowledgement gate (Task 21, FR-14.1; AT-14)', () {
    test('blocks live use until acknowledged, then persists', () async {
      final store = FakeConsentStore();
      final c = RecordingNoticeController(store);
      await c.load();
      expect(c.mustAcknowledgeBeforeUse, isTrue);
      await c.acknowledge();
      expect(c.mustAcknowledgeBeforeUse, isFalse);
      // Persisted: a fresh controller sees the acknowledgement.
      final c2 = RecordingNoticeController(store);
      await c2.load();
      expect(c2.mustAcknowledgeBeforeUse, isFalse);
    });

    test('notice text is dash-free (NFR-10)', () {
      expect(kRecordingNoticeText.contains('\u2014'), isFalse);
      expect(kRecordingNoticeText.contains('\u2013'), isFalse);
    });

    test('notice is informed consent: names cloud processing, retention and erase (HIGH-11)',
        () {
      final lower = kRecordingNoticeText.toLowerCase();
      // Clarity Mode cloud ASR + cloud assistant are disclosed.
      expect(lower, contains('clarity mode'));
      expect(lower, contains('cloud'));
      // Privacy Mode on device is disclosed.
      expect(lower, contains('privacy mode'));
      // 90 day retention is stated.
      expect(kRecordingNoticeText, contains('90 days'));
      // The erase path is named.
      expect(lower, contains('erase'));
      expect(lower, contains('settings'));
    });
  });

  group('Audible door notice toggle (Task 21, FR-14.3; AT-14)', () {
    test('is off by default', () async {
      final c = RecordingNoticeController(FakeConsentStore());
      await c.load();
      expect(c.audibleNoticeEnabled, isFalse);
    });

    test('can be enabled and persists', () async {
      final store = FakeConsentStore();
      final c = RecordingNoticeController(store);
      await c.load();
      await c.setAudibleNoticeEnabled(true);
      expect(c.audibleNoticeEnabled, isTrue);
      expect(await store.audibleNoticeEnabled(), isTrue);
    });
  });

  group('Session-start resolution (Task 21, FR-14.3, FR-14.3a; AT-14)', () {
    test('no audible notice: transcribe normally regardless of outbound', () async {
      final c = RecordingNoticeController(FakeConsentStore());
      await c.load();
      c.beginSession();
      expect(
        c.resolveSessionStart(outboundAvailable: true),
        SessionNoticeAction.transcribeNoNotice,
      );
      expect(
        c.resolveSessionStart(outboundAvailable: false),
        SessionNoticeAction.transcribeNoNotice,
      );
    });

    test('audible notice enabled + outbound available: play then transcribe (FR-14.3)', () async {
      final c = RecordingNoticeController(FakeConsentStore(audibleNotice: true));
      await c.load();
      c.beginSession();
      expect(
        c.resolveSessionStart(outboundAvailable: true),
        SessionNoticeAction.playAudibleThenTranscribe,
      );
    });

    test('audible notice enabled + outbound unavailable + no default: prompt (FR-14.3a)', () async {
      final c = RecordingNoticeController(FakeConsentStore(audibleNotice: true));
      await c.load();
      c.beginSession();
      expect(
        c.resolveSessionStart(outboundAvailable: false),
        SessionNoticeAction.promptComplianceFallback,
      );
    });

    test('the chosen fallback is honored for the whole session (FR-14.3a)', () async {
      final c = RecordingNoticeController(FakeConsentStore(audibleNotice: true));
      await c.load();
      c.beginSession();
      await c.chooseComplianceFallback(ComplianceChoice.continueWithoutNotice);
      // Same session: honored on every subsequent resolve.
      expect(
        c.resolveSessionStart(outboundAvailable: false),
        SessionNoticeAction.continueWithoutNotice,
      );
      expect(
        c.resolveSessionStart(outboundAvailable: false),
        SessionNoticeAction.continueWithoutNotice,
      );
    });

    test('disable-transcription choice is honored for the session (FR-14.3a)', () async {
      final c = RecordingNoticeController(FakeConsentStore(audibleNotice: true));
      await c.load();
      c.beginSession();
      await c.chooseComplianceFallback(ComplianceChoice.disableTranscription);
      expect(
        c.resolveSessionStart(outboundAvailable: false),
        SessionNoticeAction.disableTranscription,
      );
    });

    test('a remembered default applies to future sessions (FR-14.3a)', () async {
      final store = FakeConsentStore(audibleNotice: true);
      final c = RecordingNoticeController(store);
      await c.load();
      c.beginSession();
      await c.chooseComplianceFallback(
        ComplianceChoice.continueWithoutNotice,
        rememberAsDefault: true,
      );
      // A brand new controller/session picks up the remembered default.
      final c2 = RecordingNoticeController(store);
      await c2.load();
      c2.beginSession();
      expect(
        c2.resolveSessionStart(outboundAvailable: false),
        SessionNoticeAction.continueWithoutNotice,
      );
    });

    test('beginSession clears the per-session choice so it is re-evaluated', () async {
      final c = RecordingNoticeController(FakeConsentStore(audibleNotice: true));
      await c.load();
      c.beginSession();
      await c.chooseComplianceFallback(
        ComplianceChoice.continueWithoutNotice,
        rememberAsDefault: false,
      );
      expect(
        c.resolveSessionStart(outboundAvailable: false),
        SessionNoticeAction.continueWithoutNotice,
      );
      // New session, no default remembered: prompt again.
      c.beginSession();
      expect(
        c.resolveSessionStart(outboundAvailable: false),
        SessionNoticeAction.promptComplianceFallback,
      );
    });
  });
}
