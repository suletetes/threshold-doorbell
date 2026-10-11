// Tests for the OAuth deep-link handoff (FR-1.5, FR-1.6, HIGH-18, H-2): the
// pure parser and the exchange contract against POST /oauth/exchange, plus the
// ProductionAuthPort wiring that joins them. All headless, no device, no
// network.

import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/app/production_adapters.dart';
import 'package:threshold/session/auth_deep_link.dart';
import 'package:threshold/session/auth_port.dart';

/// A fake transport that records the request and returns a scripted response,
/// so the exchange contract is exercised without any real network.
class _FakeTransport implements AuthExchangeTransport {
  _FakeTransport(this._response);

  _FakeTransport.throwing() : _response = null;

  final AuthExchangeResponse? _response;

  String? lastPath;
  Map<String, Object?>? lastBody;

  @override
  Future<AuthExchangeResponse> postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    lastPath = path;
    lastBody = body;
    final response = _response;
    if (response == null) {
      throw StateError('transport failure');
    }
    return response;
  }
}

void main() {
  group('parseAuthDeepLink (H-2)', () {
    test('a code link yields the one-time code', () {
      final result = parseAuthDeepLink(
        Uri.parse('threshold://auth/complete?code=abc123'),
      );
      expect(result, isA<AuthDeepLinkCode>());
      expect((result as AuthDeepLinkCode).code, 'abc123');
    });

    test('an error link yields the provider error', () {
      final result = parseAuthDeepLink(
        Uri.parse('threshold://auth/complete?error=access_denied'),
      );
      expect(result, isA<AuthDeepLinkError>());
      expect((result as AuthDeepLinkError).error, 'access_denied');
    });

    test('a link with neither code nor error is invalid', () {
      final result = parseAuthDeepLink(
        Uri.parse('threshold://auth/complete'),
      );
      expect(result, isA<AuthDeepLinkInvalid>());
    });

    test('an empty code falls back to invalid', () {
      final result = parseAuthDeepLink(
        Uri.parse('threshold://auth/complete?code='),
      );
      expect(result, isA<AuthDeepLinkInvalid>());
    });

    test('a non-empty code wins over an error', () {
      final result = parseAuthDeepLink(
        Uri.parse('threshold://auth/complete?code=abc123&error=access_denied'),
      );
      expect(result, isA<AuthDeepLinkCode>());
      expect((result as AuthDeepLinkCode).code, 'abc123');
    });

    test('a foreign scheme is invalid', () {
      final result = parseAuthDeepLink(
        Uri.parse('https://auth/complete?code=abc123'),
      );
      expect(result, isA<AuthDeepLinkInvalid>());
    });

    test('a foreign host is invalid', () {
      final result = parseAuthDeepLink(
        Uri.parse('threshold://other/complete?code=abc123'),
      );
      expect(result, isA<AuthDeepLinkInvalid>());
    });
  });

  group('BackendAuthExchangeClient (H-2, HIGH-18)', () {
    test('a 200 with a session verifies and posts the code to /oauth/exchange',
        () async {
      final transport = _FakeTransport(
        const AuthExchangeResponse(
          statusCode: 200,
          body: '{"session":"token-xyz","expiresAt":"2026-01-01T00:00:00.000Z"}',
        ),
      );
      final client = BackendAuthExchangeClient(transport);

      final result = await client.exchange('abc123');

      expect(result, AuthResult.verified);
      expect(transport.lastPath, '/oauth/exchange');
      expect(transport.lastBody, <String, Object?>{'code': 'abc123'});
    });

    test('a non-200 response fails', () async {
      final transport = _FakeTransport(
        const AuthExchangeResponse(
          statusCode: 401,
          body: '{"error":{"code":"unauthorized"}}',
        ),
      );
      final result = await BackendAuthExchangeClient(transport).exchange('nope');
      expect(result, AuthResult.failed);
    });

    test('a 200 missing a session fails', () async {
      final transport = _FakeTransport(
        const AuthExchangeResponse(statusCode: 200, body: '{"expiresAt":"x"}'),
      );
      final result = await BackendAuthExchangeClient(transport).exchange('abc');
      expect(result, AuthResult.failed);
    });

    test('a 200 with a non-JSON body fails', () async {
      final transport = _FakeTransport(
        const AuthExchangeResponse(statusCode: 200, body: 'not json'),
      );
      final result = await BackendAuthExchangeClient(transport).exchange('abc');
      expect(result, AuthResult.failed);
    });

    test('an empty code fails without touching the transport', () async {
      final transport = _FakeTransport(
        const AuthExchangeResponse(statusCode: 200, body: '{"session":"x"}'),
      );
      final result = await BackendAuthExchangeClient(transport).exchange('');
      expect(result, AuthResult.failed);
      expect(transport.lastPath, isNull);
    });

    test('a transport failure fails', () async {
      final transport = _FakeTransport.throwing();
      final result = await BackendAuthExchangeClient(transport).exchange('abc');
      expect(result, AuthResult.failed);
    });
  });

  group('ProductionAuthPort.completeFromDeepLink (H-2, HIGH-09)', () {
    test('a code link redeems through the exchange client and verifies',
        () async {
      final transport = _FakeTransport(
        const AuthExchangeResponse(
          statusCode: 200,
          body: '{"session":"token-xyz","expiresAt":"2026-01-01T00:00:00.000Z"}',
        ),
      );
      final port = ProductionAuthPort(
        exchangeClient: BackendAuthExchangeClient(transport),
      );

      final result = await port.completeFromDeepLink(
        Uri.parse('threshold://auth/complete?code=abc123'),
      );

      expect(result, AuthResult.verified);
      expect(transport.lastBody, <String, Object?>{'code': 'abc123'});
    });

    test('an error link does not resume the session', () async {
      final transport = _FakeTransport(
        const AuthExchangeResponse(statusCode: 200, body: '{"session":"x"}'),
      );
      final port = ProductionAuthPort(
        exchangeClient: BackendAuthExchangeClient(transport),
      );

      final result = await port.completeFromDeepLink(
        Uri.parse('threshold://auth/complete?error=access_denied'),
      );

      expect(result, AuthResult.failed);
      // The error short-circuits before any exchange POST.
      expect(transport.lastPath, isNull);
    });

    test('an invalid link does not resume the session', () async {
      final port = ProductionAuthPort(
        exchangeClient: BackendAuthExchangeClient(
          _FakeTransport(
            const AuthExchangeResponse(statusCode: 200, body: '{"session":"x"}'),
          ),
        ),
      );

      final result = await port.completeFromDeepLink(
        Uri.parse('https://evil/complete?code=abc123'),
      );

      expect(result, AuthResult.failed);
    });

    test('without an exchange client the live binding fails closed', () async {
      const port = ProductionAuthPort();
      expect(
        () => port.completeFromDeepLink(
          Uri.parse('threshold://auth/complete?code=abc123'),
        ),
        throwsA(isA<DeviceBindingUnavailable>()),
      );
    });

    test('the live reauthenticate step is still deferred', () async {
      const port = ProductionAuthPort();
      expect(
        port.reauthenticate,
        throwsA(isA<DeviceBindingUnavailable>()),
      );
    });
  });
}
