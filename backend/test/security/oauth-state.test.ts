import { describe, it, expect } from 'vitest';
import { decodeState, encodeState } from '../../src/security/oauth-state.js';

const SECRET = 'a-sufficiently-long-session-secret';

describe('oauth state token (stateless PKCE carry + CSRF)', () => {
  it('round-trips nonce and verifier', () => {
    const s = encodeState('nonce-1', 'verifier-1', SECRET);
    const txn = decodeState(s, SECRET);
    expect(txn).not.toBeNull();
    expect(txn!.nonce).toBe('nonce-1');
    expect(txn!.codeVerifier).toBe('verifier-1');
  });

  it('rejects a tampered state (FR-1.3 state mismatch)', () => {
    const s = encodeState('nonce-1', 'verifier-1', SECRET);
    const tampered = s.slice(0, -1) + (s.endsWith('A') ? 'B' : 'A');
    expect(decodeState(tampered, SECRET)).toBeNull();
  });

  it('rejects a state signed with a different secret', () => {
    const s = encodeState('nonce-1', 'verifier-1', SECRET);
    expect(decodeState(s, 'other-secret')).toBeNull();
  });

  it('rejects an expired state', () => {
    const now = Date.now();
    const s = encodeState('nonce-1', 'verifier-1', SECRET, now);
    expect(decodeState(s, SECRET, now + 11 * 60 * 1000)).toBeNull();
  });

  it('rejects undefined and malformed state', () => {
    expect(decodeState(undefined, SECRET)).toBeNull();
    expect(decodeState('garbage', SECRET)).toBeNull();
  });
});
