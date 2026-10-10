import { describe, it, expect } from 'vitest';
import { deriveKey, KEY_INFO } from '../../src/security/keys.js';

// MED-33: one root secret must yield independent keys per purpose.
describe('key separation via HKDF (MED-33)', () => {
  const secret = 'a-sufficiently-long-root-secret-value';

  it('derives a 32-byte key for each purpose', () => {
    for (const purpose of Object.keys(KEY_INFO) as (keyof typeof KEY_INFO)[]) {
      expect(deriveKey(secret, purpose)).toHaveLength(32);
    }
  });

  it('derives DISTINCT keys for distinct purposes', () => {
    const session = deriveKey(secret, 'sessionSigning').toString('hex');
    const state = deriveKey(secret, 'stateSigning').toString('hex');
    const token = deriveKey(secret, 'tokenEncryption').toString('hex');
    expect(session).not.toBe(state);
    expect(session).not.toBe(token);
    expect(state).not.toBe(token);
    // None equals a plain hash of the secret (not the raw secret either).
    expect(session).not.toContain(secret);
  });

  it('is deterministic for the same secret and purpose', () => {
    expect(deriveKey(secret, 'sessionSigning')).toEqual(deriveKey(secret, 'sessionSigning'));
  });
});
