// Recording-notice controller (Task 21, FR-14.1, FR-14.3, FR-14.3a; AT-14).
// Owns the first-run acknowledgement gate and resolves what to do at session
// start regarding the audible door notice and the compliance fallback, honoring
// the resident's choice for the whole session and remembering the default. A
// ChangeNotifier so the first-run screen and Settings update.

import 'package:flutter/foundation.dart';

import 'recording_notice.dart';

class RecordingNoticeController extends ChangeNotifier {
  RecordingNoticeController(this._store);

  final ConsentStore _store;

  bool _acknowledged = false;
  bool _audibleNoticeEnabled = false;
  ComplianceChoice? _defaultChoice;

  /// The choice active for the CURRENT session (FR-14.3a "honor for the whole
  /// session"), null when no session-specific choice has been made.
  ComplianceChoice? _sessionChoice;

  bool get isAcknowledged => _acknowledged;
  bool get audibleNoticeEnabled => _audibleNoticeEnabled;
  ComplianceChoice? get defaultComplianceChoice => _defaultChoice;
  ComplianceChoice? get sessionChoice => _sessionChoice;

  /// Whether the first-run gate blocks live use (FR-14.1): true until
  /// acknowledged.
  bool get mustAcknowledgeBeforeUse => !_acknowledged;

  /// Load persisted state (call once at startup).
  Future<void> load() async {
    _acknowledged = await _store.isAcknowledged();
    _audibleNoticeEnabled = await _store.audibleNoticeEnabled();
    _defaultChoice = await _store.defaultComplianceChoice();
    notifyListeners();
  }

  /// The resident acknowledges the first-run notice (FR-14.1). Persisted so it
  /// is a one-time gate.
  Future<void> acknowledge() async {
    _acknowledged = true;
    await _store.setAcknowledged(true);
    notifyListeners();
  }

  /// Toggle the optional audible door notice (FR-14.3), default off.
  Future<void> setAudibleNoticeEnabled(bool value) async {
    _audibleNoticeEnabled = value;
    await _store.setAudibleNoticeEnabled(value);
    notifyListeners();
  }

  /// Begin a new session: clear any prior per-session choice so the fallback is
  /// re-evaluated (FR-14.3a applies per session).
  void beginSession() {
    _sessionChoice = null;
  }

  /// Resolve what to do at session start (design §6). [outboundAvailable] is the
  /// sticky probe result for the session.
  SessionNoticeAction resolveSessionStart({required bool outboundAvailable}) {
    if (!_audibleNoticeEnabled) {
      // No audible notice requested: transcribe normally.
      return SessionNoticeAction.transcribeNoNotice;
    }
    if (outboundAvailable) {
      // Audible notice enabled and playable via the outbound path (FR-14.3).
      return SessionNoticeAction.playAudibleThenTranscribe;
    }
    // Audible notice enabled but outbound unavailable (FR-14.3a). A prior choice
    // for THIS session wins; otherwise a remembered default; otherwise prompt.
    final choice = _sessionChoice ?? _defaultChoice;
    switch (choice) {
      case ComplianceChoice.continueWithoutNotice:
        return SessionNoticeAction.continueWithoutNotice;
      case ComplianceChoice.disableTranscription:
        return SessionNoticeAction.disableTranscription;
      case null:
        return SessionNoticeAction.promptComplianceFallback;
    }
  }

  /// Record the resident's compliance-fallback choice (FR-14.3a). [rememberAsDefault]
  /// persists it as the default for future sessions. The choice is honored for
  /// the whole current session.
  ///
  /// [rememberAsDefault] defaults to FALSE (MED-06): a one-time per-session
  /// choice must not silently become the persisted legal default. The dialog
  /// surfaces an explicit, default-off "remember my choice" checkbox and passes
  /// its value here, so the resident opts in to remembering rather than having
  /// it chosen for them.
  Future<void> chooseComplianceFallback(
    ComplianceChoice choice, {
    bool rememberAsDefault = false,
  }) async {
    _sessionChoice = choice;
    if (rememberAsDefault) {
      _defaultChoice = choice;
      await _store.setDefaultComplianceChoice(choice);
    }
    notifyListeners();
  }
}
