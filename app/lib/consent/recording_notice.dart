// Recording notice and compliance fallback (Task 21, FR-14.1..FR-14.4; AT-14).
//
// FR-14.1: present, on first use and in Settings, a plain-language notice that
//   Threshold transcribes what visitors say, and require one-time
//   acknowledgement (a first-run gate before any live use).
// FR-14.3: offer an optional, default-off audible door notice played at session
//   start via the outbound-audio path.
// FR-14.3a: IF the audible notice is enabled but outbound audio is unavailable
//   (Captions-Only), do NOT silently transcribe. Present a choice: continue with
//   captions without the audible notice (acknowledging responsibility), or
//   disable transcription for that session. Honor the choice for the whole
//   session and remember the default.
//
// Pure logic driven by an injectable persistence store so the gate, the
// default-off toggle, and the compliance fallback are exhaustively unit-testable
// without a device. The audible-notice audio itself is played via the ReplyPort
// (outbound-audio path) on device; here we own the policy.

import 'dart:async';

/// The exact first-run notice text (FR-14.1). Plain language, dash-free (NFR-10).
const String kRecordingNoticeText =
    'Threshold turns what your visitor says into text so you can read it. No '
    'visitor audio or video is stored. In Privacy Mode everything stays on your '
    'phone. You are responsible for lawful use where you live.';

/// Persists the first-run acknowledgement and the audible-notice preference. The
/// live binding wraps shared_preferences; the fake keeps values in memory.
abstract class ConsentStore {
  Future<bool> isAcknowledged();
  Future<void> setAcknowledged(bool value);
  Future<bool> audibleNoticeEnabled();
  Future<void> setAudibleNoticeEnabled(bool value);

  /// The remembered default for the FR-14.3a compliance fallback choice.
  Future<ComplianceChoice?> defaultComplianceChoice();
  Future<void> setDefaultComplianceChoice(ComplianceChoice choice);
}

/// The resident's choice when the audible notice is enabled but outbound audio
/// is unavailable (FR-14.3a).
enum ComplianceChoice {
  /// Continue with captions without the audible notice, acknowledging
  /// responsibility.
  continueWithoutNotice,

  /// Disable transcription for that session.
  disableTranscription,
}

/// In-memory fake store for tests and local runs.
class FakeConsentStore implements ConsentStore {
  FakeConsentStore({
    bool acknowledged = false,
    bool audibleNotice = false,
    ComplianceChoice? defaultChoice,
  })  : _acknowledged = acknowledged,
        _audibleNotice = audibleNotice,
        _defaultChoice = defaultChoice;

  bool _acknowledged;
  bool _audibleNotice;
  ComplianceChoice? _defaultChoice;

  @override
  Future<bool> isAcknowledged() async => _acknowledged;

  @override
  Future<void> setAcknowledged(bool value) async => _acknowledged = value;

  @override
  Future<bool> audibleNoticeEnabled() async => _audibleNotice;

  @override
  Future<void> setAudibleNoticeEnabled(bool value) async => _audibleNotice = value;

  @override
  Future<ComplianceChoice?> defaultComplianceChoice() async => _defaultChoice;

  @override
  Future<void> setDefaultComplianceChoice(ComplianceChoice choice) async =>
      _defaultChoice = choice;
}

/// What the app should do at session start regarding the recording notice and
/// the compliance fallback (design §6 "Audible notice enabled but unavailable").
enum SessionNoticeAction {
  /// Play the audible door notice via the outbound path, then transcribe
  /// (audible notice enabled AND outbound available).
  playAudibleThenTranscribe,

  /// Transcribe with no audible notice (audible notice disabled; outbound state
  /// is irrelevant since no notice was requested).
  transcribeNoNotice,

  /// The audible notice is enabled but outbound is unavailable and no default
  /// choice is remembered: the resident must be prompted (FR-14.3a).
  promptComplianceFallback,

  /// Remembered default: continue with captions, no audible notice (FR-14.3a).
  continueWithoutNotice,

  /// Remembered default: disable transcription for this session (FR-14.3a).
  disableTranscription,
}
