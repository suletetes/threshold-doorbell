// OAuth 2.0 PKCE and CSRF-state helpers (FR-1.1). A cryptographically random
// verifier and state; the S256 code challenge is derived from the verifier.

import { createHash, randomBytes } from 'node:crypto';

export interface PkcePair {
  codeVerifier: string;
  codeChallenge: string;
  challengeMethod: 'S256';
}

/** RFC 7636 code verifier: 43 to 128 chars, base64url of 32 random bytes = 43. */
export function generateCodeVerifier(): string {
  return randomBytes(32).toString('base64url');
}

/** S256 challenge = base64url(SHA256(verifier)). */
export function deriveCodeChallenge(codeVerifier: string): string {
  return createHash('sha256').update(codeVerifier).digest('base64url');
}

export function createPkcePair(): PkcePair {
  const codeVerifier = generateCodeVerifier();
  return {
    codeVerifier,
    codeChallenge: deriveCodeChallenge(codeVerifier),
    challengeMethod: 'S256',
  };
}

/** Cryptographically random CSRF state value (FR-1.1). */
export function generateState(): string {
  return randomBytes(32).toString('base64url');
}
