import { describe, it, expect } from 'vitest';
import {
  decodeState,
  encodeState,
  hashNonce,
  nonceCookieMatches,
} from '../../src/security/oauth-state.js';

const SECRET = 'a-sufficiently-long-session-secret';

describe('oauth state token (nonce-only front channel + CSRF, HIGH-17)', () => {
  it('round-trips the nonce and never carries a PKCE verifier', () => {
    const s = encodeState('nonce-1', SECRET);
    const payload = decodeState(s, SECRET);
    expect(payload).not.toBeNull();
    expect(payload!.nonce).toBe('nonce-1');
    // The verifier must not travel in the front channel (HIGH-17).
    expect(JSON.stringify(payload)).not.toContain('codeVerifier');
    const decoded = JSON.parse(Buffer.from(s.split('.')[0]!, 'base64url').toString('utf8'));
    expect(decoded.codeVerifier).toBeUndefined();
  });

  it('rejects a tampered state (FR-1.3 state mismatch)', () => {
    const s = encodeState('nonce-1', SECRET);
    const tampered = s.slice(0, -1) + (s.endsWith('A') ? 'B' : 'A');
    expect(decodeState(tampered, SECRET)).toBeNull();
  });

  it('rejects a state signed with a different secret', () => {
    const s = encodeState('nonce-1', SECRET);
    expect(decodeState(s, 'other-secret')).toBeNull();
  });

  it('rejects an expired state', () => {
    const now = Date.now();
    const s = encodeState('nonce-1', SECRET, now);
    expect(decodeState(s, SECRET, now + 11 * 60 * 1000)).toBeNull();
  });

  it('rejects undefined and malformed state', () => {
    expect(decodeState(undefined, SECRET)).toBeNull();
    expect(decodeState('garbage', SECRET)).toBeNull();
  });

  it('binds state to the browser via H(nonce) (HIGH-16)', () => {
    const expected = hashNonce('nonce-1', SECRET);
    // The cookie value is a hash, not the raw nonce.
    expect(expected).not.toBe('nonce-1');
    expect(nonceCookieMatches(expected, hashNonce('nonce-1', SECRET))).toBe(true);
    expect(nonceCookieMatches(hashNonce('other', SECRET), hashNonce('nonce-1', SECRET))).toBe(false);
    expect(nonceCookieMatches(undefined, expected)).toBe(false);
    expect(nonceCookieMatches('', expected)).toBe(false);
  });
});
