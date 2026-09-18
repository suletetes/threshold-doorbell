// App-to-backend session credential (design.md §7). A signed, stateless bearer
// binding a residentSub with a 30-minute idle expiry. HMAC-SHA256 signed with
// the session secret. The device stores ONLY this credential (never Ring tokens,
// FR-1.6). Expiry drives the unified auth-recovery flow (FR-1.5).

import { createHmac, timingSafeEqual } from 'node:crypto';

export const SESSION_IDLE_MS = 30 * 60 * 1000; // 30 minutes (design.md §7)

export interface SessionClaims {
  sub: string; // residentSub, server-derived
  iat: number; // issued-at (epoch ms)
  exp: number; // expiry (epoch ms)
}

function sign(payload: string, secret: string): string {
  return createHmac('sha256', secret).update(payload).digest('base64url');
}

/** Issue a session token for a residentSub. */
export function issueSession(sub: string, secret: string, now = Date.now()): string {
  const claims: SessionClaims = { sub, iat: now, exp: now + SESSION_IDLE_MS };
  const payload = Buffer.from(JSON.stringify(claims), 'utf8').toString('base64url');
  const sig = sign(payload, secret);
  return `${payload}.${sig}`;
}

/**
 * Verify a session token. Returns claims when valid and unexpired, otherwise
 * null. Signature comparison is constant-time. A null result triggers the
 * unified recovery flow at the route layer (401 unauthorized).
 */
export function verifySession(
  token: string | undefined,
  secret: string,
  now = Date.now(),
): SessionClaims | null {
  if (!token) return null;
  const dot = token.indexOf('.');
  if (dot <= 0) return null;
  const payload = token.slice(0, dot);
  const sig = token.slice(dot + 1);
  const expected = sign(payload, secret);

  const sigBuf = Buffer.from(sig);
  const expBuf = Buffer.from(expected);
  if (sigBuf.length !== expBuf.length || !timingSafeEqual(sigBuf, expBuf)) {
    return null;
  }

  let claims: SessionClaims;
  try {
    claims = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as SessionClaims;
  } catch {
    return null;
  }
  if (typeof claims.sub !== 'string' || claims.sub === '') return null;
  if (typeof claims.exp !== 'number' || now >= claims.exp) return null;
  return claims;
}

export const SESSION_COOKIE = 'threshold_session';
