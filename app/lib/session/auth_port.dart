// App-to-backend authentication port (FR-1.5, FR-4.8; HIGH-09). When an
// app/backend session expires mid-use, the auth-recovery prompt's "Sign in"
// action must actually re-authenticate the resident and only resume the session
// once a fresh token is verified. The real binding performs the OAuth / backend
// session exchange over HTTPS and is device/network bound, so it sits behind
// this interface with a fake for headless widget tests.
//
// The real backend session client is DEFERRED: it needs a device and live
// network to exchange and verify a token, which this environment cannot do.
// This port plus its fake is the wiring that lets the UI resume only after a
// verified token instead of the old stub that called completeAuthRecovery with
// success hard-coded to true (HIGH-09).

import 'dart:async';

/// The outcome of a re-authentication attempt.
enum AuthResult {
  /// A fresh token was obtained and verified; the session may resume.
  verified,

  /// The resident cancelled, or re-authentication failed; do not resume.
  failed,
}

/// Re-authenticates the resident after a mid-session expiry (FR-1.5, FR-4.8).
abstract class AuthPort {
  /// Run the re-authentication flow and return whether a fresh token was
  /// verified. Only [AuthResult.verified] may resume the session (HIGH-09).
  Future<AuthResult> reauthenticate();
}

/// Deterministic fake. Tests script the result (and can script a first failure
/// then success). Records the number of attempts for assertions.
class FakeAuthPort implements AuthPort {
  FakeAuthPort({List<AuthResult>? plan})
      : _plan = List<AuthResult>.from(
          plan ?? const <AuthResult>[AuthResult.verified],
        );

  final List<AuthResult> _plan;
  int attempts = 0;

  @override
  Future<AuthResult> reauthenticate() async {
    attempts++;
    return _plan.isEmpty ? AuthResult.verified : _plan.removeAt(0);
  }
}
