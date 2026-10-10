// OAuth transaction state. The `state` parameter that travels in the front
// channel is a signed, expiring token carrying ONLY the random CSRF nonce
// (HIGH-17: the PKCE verifier is NOT in the front channel; it is held
// server-side keyed by the nonce, see OAuthTxnStorePort). The state is bound to
// the browser by an HttpOnly cookie holding H(nonce) (HIGH-16): the callback
// requires the cookie and that its hash matches the nonce in the state, and the
// server-side nonce entry is single-use so a replayed state is rejected.

import { createHmac, timingSafeEqual } from 'node:crypto';

const OAUTH_TXN_TTL_MS = 10 * 60 * 1000; // 10 minutes to complete the redirect

export interface StatePayload {
  nonce: string; // random CSRF nonce
  iat: number;
  exp: number;
}

function sign(payload: string, secret: string): string {
  return createHmac('sha256', secret).update(payload).digest('base64url');
}

/** H(nonce): the value stored in the browser cookie that binds state to client. */
export function hashNonce(nonce: string, secret: string): string {
  return createHmac('sha256', secret).update(`oauth-nonce:${nonce}`).digest('base64url');
}

/** Encode a signed state token carrying ONLY the CSRF nonce (no PKCE verifier). */
export function encodeState(nonce: string, secret: string, now = Date.now()): string {
  const payload: StatePayload = { nonce, iat: now, exp: now + OAUTH_TXN_TTL_MS };
  const encoded = Buffer.from(JSON.stringify(payload), 'utf8').toString('base64url');
  return `${encoded}.${sign(encoded, secret)}`;
}

/**
 * Decode and verify a state token. Returns the payload when the signature is
 * valid and unexpired, otherwise null. A null result is a state mismatch
 * (FR-1.3) and the callback must be rejected without storing any token.
 */
export function decodeState(
  state: string | undefined,
  secret: string,
  now = Date.now(),
): StatePayload | null {
  if (!state) return null;
  const dot = state.indexOf('.');
  if (dot <= 0) return null;
  const encoded = state.slice(0, dot);
  const sig = state.slice(dot + 1);
  const expected = sign(encoded, secret);

  const a = Buffer.from(sig);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !timingSafeEqual(a, b)) return null;

  let payload: StatePayload;
  try {
    payload = JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8')) as StatePayload;
  } catch {
    return null;
  }
  if (typeof payload.nonce !== 'string' || payload.nonce === '') return null;
  if (typeof payload.exp !== 'number' || now >= payload.exp) return null;
  return payload;
}

/** Constant-time comparison for the state-binding cookie against H(nonce). */
export function nonceCookieMatches(cookieValue: string | undefined, expected: string): boolean {
  if (typeof cookieValue !== 'string' || cookieValue === '') return false;
  const a = Buffer.from(cookieValue);
  const b = Buffer.from(expected);
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

/** Cookie that binds the OAuth state to the browser (HIGH-16). */
export const OAUTH_STATE_COOKIE = 'threshold_oauth_state';
