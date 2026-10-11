// OAuth deep-link handoff for the native app (FR-1.5, FR-1.6, HIGH-18, H-2).
//
// The backend OAuth callback 302-redirects to config.appDeepLink (default
// threshold://auth/complete) carrying either a one-time app code (?code=) or a
// provider error (?error=). The Android VIEW/BROWSABLE intent-filter delivers
// that link back to the activity; this file turns the raw [Uri] into a typed
// result and defines the HTTPS exchange contract against POST /oauth/exchange.
//
// Only the parser and the exchange-contract logic live here, and both are pure
// and headless so they are fully covered by `flutter test`. The live link
// listener and the real HTTPS transport are device/network bound and stay in
// the production adapter, which still fails closed where that runtime cannot
// run. The important fix is that the server-side one-time-code handoff now has
// a real client half instead of being orphaned.

import 'dart:async';
import 'dart:convert';

import 'auth_port.dart';

/// The scheme the backend redirects to (config.appDeepLink default). Links with
/// any other scheme or host are not ours and parse to [AuthDeepLinkInvalid].
const String kAuthDeepLinkScheme = 'threshold';

/// The host the backend redirects to (threshold://auth/complete).
const String kAuthDeepLinkHost = 'auth';

/// The parsed outcome of an incoming OAuth deep link. One of:
/// [AuthDeepLinkCode] (a redeemable one-time code), [AuthDeepLinkError] (the
/// provider reported an error) or [AuthDeepLinkInvalid] (not a link we own, or
/// it carries neither a code nor an error).
sealed class AuthDeepLink {
  const AuthDeepLink();
}

/// The link carried a non-empty one-time app code to redeem at /oauth/exchange.
class AuthDeepLinkCode extends AuthDeepLink {
  const AuthDeepLinkCode(this.code);
  final String code;
}

/// The link carried a non-empty provider error (for example access_denied).
class AuthDeepLinkError extends AuthDeepLink {
  const AuthDeepLinkError(this.error);
  final String error;
}

/// The link was not an OAuth completion we recognise, or carried neither a code
/// nor an error.
class AuthDeepLinkInvalid extends AuthDeepLink {
  const AuthDeepLinkInvalid();
}

/// Parse an incoming deep link into a typed [AuthDeepLink]. Pure and total: it
/// never throws and never performs any network work.
///
/// A link is recognised only when its scheme is [kAuthDeepLinkScheme] and its
/// host is [kAuthDeepLinkHost]; a foreign scheme or host yields
/// [AuthDeepLinkInvalid]. A non-empty `code` wins over an `error`; an empty or
/// absent `code` falls back to a non-empty `error`; anything else is invalid.
AuthDeepLink parseAuthDeepLink(Uri uri) {
  if (uri.scheme != kAuthDeepLinkScheme || uri.host != kAuthDeepLinkHost) {
    return const AuthDeepLinkInvalid();
  }
  final code = uri.queryParameters['code'];
  if (code != null && code.isNotEmpty) {
    return AuthDeepLinkCode(code);
  }
  final error = uri.queryParameters['error'];
  if (error != null && error.isNotEmpty) {
    return AuthDeepLinkError(error);
  }
  return const AuthDeepLinkInvalid();
}

/// A minimal HTTP transport the exchange client depends on, so tests can inject
/// a fake without touching the network. The real binding in the production
/// adapter wraps an HTTPS client; this interface keeps the exchange contract
/// pure and testable.
abstract class AuthExchangeTransport {
  /// POST [body] as JSON to the backend path [path] and return the response.
  Future<AuthExchangeResponse> postJson(
    String path,
    Map<String, Object?> body,
  );
}

/// The transport-level result of an exchange POST: an HTTP status and the raw
/// response body. The exchange client interprets these per the server contract.
class AuthExchangeResponse {
  const AuthExchangeResponse({required this.statusCode, required this.body});
  final int statusCode;
  final String body;
}

/// Redeems the one-time app code for the session credential over HTTPS
/// (HIGH-18, FR-1.6). The backend POST /oauth/exchange returns 200 with a JSON
/// `{session, expiresAt}` body on success, or the unified unauthorized signal
/// (non-200) on an unknown, consumed or expired code (FR-1.5).
abstract class AuthExchangeClient {
  /// Exchange [code] and return [AuthResult.verified] only when the backend
  /// returned a usable session credential; any other outcome is
  /// [AuthResult.failed].
  Future<AuthResult> exchange(String code);
}

/// The pure exchange contract against POST /oauth/exchange, driven by an
/// injectable [AuthExchangeTransport]. The live production adapter supplies a
/// real HTTPS transport; tests supply a fake one. This verifies the server
/// contract without any device or network: a 200 carrying a non-empty `session`
/// yields [AuthResult.verified]; a non-200 status, a non-JSON body, or a body
/// missing a usable `session` yields [AuthResult.failed].
class BackendAuthExchangeClient implements AuthExchangeClient {
  const BackendAuthExchangeClient(this._transport);

  /// The backend path the one-time code is redeemed at (see oauth.ts).
  static const String exchangePath = '/oauth/exchange';

  final AuthExchangeTransport _transport;

  @override
  Future<AuthResult> exchange(String code) async {
    if (code.isEmpty) {
      return AuthResult.failed;
    }
    final AuthExchangeResponse response;
    try {
      response = await _transport.postJson(
        exchangePath,
        <String, Object?>{'code': code},
      );
    } catch (_) {
      // A transport failure is a failed re-authentication; never resume on it.
      return AuthResult.failed;
    }
    if (response.statusCode != 200) {
      return AuthResult.failed;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      return AuthResult.failed;
    }
    if (decoded is! Map<String, Object?>) {
      return AuthResult.failed;
    }
    final session = decoded['session'];
    if (session is String && session.isNotEmpty) {
      return AuthResult.verified;
    }
    return AuthResult.failed;
  }
}
