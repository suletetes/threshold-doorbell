// App-to-backend session credential (design.md §7). A signed, stateless bearer
// binding a residentSub with a 30-minute idle expiry. HMAC-SHA256 signed with
// the session secret. The device stores ONLY this credential (never Ring tokens,
// FR-1.6). Expiry drives the unified auth-recovery flow (FR-1.5).

import { createHmac, timingSafeEqual } from 'node:crypto';
import { deriveKey } from './keys.js';

// NIT-04: `exp` is an ABSOLUTE expiry 30 minutes after issue. The idle-reset
// behaviour is achieved by re-issuing the cookie on activity (slideSession /
// /oauth/refresh), which mints a fresh token with a new absolute window.
export const SESSION_ABSOLUTE_MS = 30 * 60 * 1000; // 30 minutes (design.md §7)
// Backwards-compatible alias retained for existing call sites.
export const SESSION_IDLE_MS = SESSION_ABSOLUTE_MS;

// Token type (MED-33): a `typ` claim prevents a session token from being
// accepted where a differently-purposed signed token is expected.
const SESSION_TYP = 'session';

export interface SessionClaims {
  typ?: string; // token type (MED-33); 'session' for app sessions
  sub: string; // residentSub, server-derived
  iat: number; // issued-at (epoch ms)
  exp: number; // absolute expiry (epoch ms), NIT-04
}

function sign(payload: string, secret: string): string {
  // MED-33: sign with the session-signing key, not the raw secret.
  return createHmac('sha256', deriveKey(secret, 'sessionSigning')).update(payload).digest('base64url');
}

/** Issue a session token for a residentSub with an absolute 30-minute expiry. */
export function issueSession(sub: string, secret: string, now = Date.now()): string {
  const claims: SessionClaims = { typ: SESSION_TYP, sub, iat: now, exp: now + SESSION_ABSOLUTE_MS };
  const payload = Buffer.from(JSON.stringify(claims), 'utf8').toString('base64url');
  const sig = sign(payload, secret);
  return `${payload}.${sig}`;
}

/**
 * Slide a session forward on activity: issue a fresh token with a new absolute
 * window (NIT-04). The idle timeout is the gap between the last slide and now.
 */
export function slideSession(sub: string, secret: string, now = Date.now()): string {
  return issueSession(sub, secret, now);
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
  // MED-33: reject a token that is not a session token (type confusion). Legacy
  // tokens without a typ are tolerated for one deploy; new tokens always set it.
  if (claims.typ !== undefined && claims.typ !== SESSION_TYP) return null;
  if (typeof claims.sub !== 'string' || claims.sub === '') return null;
  if (typeof claims.exp !== 'number' || now >= claims.exp) return null;
  return claims;
}

export const SESSION_COOKIE = 'threshold_session';
