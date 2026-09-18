import { describe, it, expect } from 'vitest';
import { createHash } from 'node:crypto';
import {
  createPkcePair,
  deriveCodeChallenge,
  generateCodeVerifier,
  generateState,
} from '../../src/security/pkce.js';

describe('PKCE', () => {
  it('generates a verifier in the RFC 7636 length range', () => {
    const v = generateCodeVerifier();
    expect(v.length).toBeGreaterThanOrEqual(43);
    expect(v.length).toBeLessThanOrEqual(128);
  });

  it('derives an S256 challenge from the verifier', () => {
    const v = 'test-verifier';
    const expected = createHash('sha256').update(v).digest('base64url');
    expect(deriveCodeChallenge(v)).toBe(expected);
  });

  it('createPkcePair uses S256 and a matching challenge', () => {
    const pair = createPkcePair();
    expect(pair.challengeMethod).toBe('S256');
    expect(pair.codeChallenge).toBe(deriveCodeChallenge(pair.codeVerifier));
  });

  it('generates unique random state values', () => {
    const a = generateState();
    const b = generateState();
    expect(a).not.toBe(b);
    expect(a.length).toBeGreaterThanOrEqual(43);
  });
});
