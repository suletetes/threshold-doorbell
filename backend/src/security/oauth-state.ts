// Stateless OAuth transaction encoding. The backend runs >=2 stateless
// instances (design.md §1), so the PKCE verifier and CSRF nonce cannot live in
// per-instance memory between /oauth/start and /oauth/callback. We encode them
// into a signed, expiring token that travels as the OAuth `state` parameter.
// The signature check on callback is the CSRF/state verification (FR-1.3).

import { createHmac, timingSafeEqual } from 'node:crypto';

const OAUTH_TXN_TTL_MS = 10 * 60 * 1000; // 10 minutes to complete the redirect

export interface OAuthTxn {
  nonce: string; // random CSRF nonce
  codeVerifier: string; // PKCE verifier, kept server-side
  iat: number;
  exp: number;
}

function sign(payload: string, secret: string): string {
  return createHmac('sha256', secret).update(payload).digest('base64url');
}

/** Encode a signed state token carrying the PKCE verifier and CSRF nonce. */
export function encodeState(
  nonce: string,
  codeVerifier: string,
  secret: string,
  now = Date.now(),
): string {
  const txn: OAuthTxn = { nonce, codeVerifier, iat: now, exp: now + OAUTH_TXN_TTL_MS };
  const payload = Buffer.from(JSON.stringify(txn), 'utf8').toString('base64url');
  return `${payload}.${sign(payload, secret)}`;
}

/**
 * Decode and verify a state token. Returns the transaction when the signature
 * is valid and unexpired, otherwise null. A null result is a state mismatch
 * (FR-1.3) and the callback must be rejected without storing any token.
 */
export function decodeState(
  state: string | undefined,
  secret: string,
  now = Date.now(),
): OAuthTxn | null {
  if (!state) return null;
  const dot = state.indexOf('.');
  if (dot <= 0) return null;
  const payload = state.slice(0, dot);
  const sig = state.slice(dot + 1);
  const expected = sign(payload, secret);

  const a = Buffer.from(sig);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !timingSafeEqual(a, b)) return null;

  let txn: OAuthTxn;
  try {
    txn = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as OAuthTxn;
  } catch {
    return null;
  }
  if (typeof txn.codeVerifier !== 'string' || txn.codeVerifier === '') return null;
  if (typeof txn.nonce !== 'string' || txn.nonce === '') return null;
  if (typeof txn.exp !== 'number' || now >= txn.exp) return null;
  return txn;
}
