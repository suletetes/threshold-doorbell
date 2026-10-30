// WebSocket upgrade authentication and Origin check (MED-34).
//
// A WebSocket must NOT carry the 30-minute session bearer in the URL query
// (`?token=`), because the URL ends up in load-balancer and proxy access logs.
// We accept the credential from, in order:
//   1. the `Sec-WebSocket-Protocol` header, as a `threshold.session.<token>`
//      subprotocol value (the browser-safe way to pass a credential on a WS);
//   2. the session cookie;
//   3. a Bearer Authorization header (used by the in-process test client).
// The `?token=` query parameter is intentionally ignored.
//
// We also validate `Origin`: a request with no Origin (a native app) is allowed;
// a request WITH an Origin must match the configured allowlist, otherwise a
// malicious web page could open a cross-site WebSocket against a logged-in user.

import type { FastifyRequest } from 'fastify';
import { SESSION_COOKIE, verifySession, type SessionClaims } from './session.js';
import type { SessionInvalidationPort } from '../services/session-invalidation.js';

/** Subprotocol prefix carrying the session token on a WebSocket (MED-34). */
export const WS_SESSION_PROTOCOL_PREFIX = 'threshold.session.';

/** Extract the session token from the accepted sources (never the URL query). */
export function extractWsToken(request: FastifyRequest): string | undefined {
  const protocolHeader = request.headers['sec-websocket-protocol'];
  if (typeof protocolHeader === 'string') {
    const offered = protocolHeader.split(',').map((p) => p.trim());
    const found = offered.find((p) => p.startsWith(WS_SESSION_PROTOCOL_PREFIX));
    if (found) return found.slice(WS_SESSION_PROTOCOL_PREFIX.length);
  }
  const cookieToken = request.cookies?.[SESSION_COOKIE];
  if (cookieToken) return cookieToken;
  const auth = request.headers.authorization;
  if (typeof auth === 'string' && auth.startsWith('Bearer ')) {
    return auth.slice('Bearer '.length);
  }
  return undefined;
}

/** True when the request's Origin is allowed (absent Origin = native app = ok). */
export function isOriginAllowed(request: FastifyRequest, allowedOrigins: readonly string[]): boolean {
  const origin = request.headers.origin;
  if (typeof origin !== 'string' || origin === '') return true; // native client
  return allowedOrigins.includes(origin);
}

/**
 * Authenticate a WS upgrade: validate Origin, verify the session token from an
 * allowed source, then deny any session issued at or before an erasure cutoff
 * (HIGH-23 / H-1). Returns the claims or null. residentSub is always derived
 * from the verified credential, never from client input.
 *
 * The erasure deny-list is consulted here (mirroring the HTTP guard in
 * app.ts requireSession) so a still-valid pre-erasure bearer cannot open a
 * live /signaling session or an /asr/stream relay after DELETE /me/data.
 */
export async function authenticateWs(
  request: FastifyRequest,
  secret: string,
  allowedOrigins: readonly string[],
  sessionInvalidation: SessionInvalidationPort,
  allowDemoToken = false,
): Promise<SessionClaims | null> {
  if (!isOriginAllowed(request, allowedOrigins)) return null;
  const claims = verifySession(extractWsToken(request), secret, Date.now(), allowDemoToken);
  if (!claims) return null;
  if (await sessionInvalidation.isRevoked(claims.sub, claims.iat)) return null;
  return claims;
}
