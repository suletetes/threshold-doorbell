// Key separation via HKDF (MED-33). One configured secret must not directly
// serve three different purposes, because rotating it would invalidate every
// stored token and every live session at once, and because reusing the same key
// across contexts allows token-type confusion. We derive a distinct 32-byte key
// for each purpose with HKDF-SHA256 using a distinct `info` label, so the keys
// are independent even though they come from the same root secret.

import { hkdfSync } from 'node:crypto';

/** Distinct HKDF info labels, one per key purpose. Never reuse a label. */
export const KEY_INFO = {
  sessionSigning: 'threshold:session-signing:v1',
  stateSigning: 'threshold:oauth-state-signing:v1',
  tokenEncryption: 'threshold:ring-token-encryption:v1',
} as const;

export type KeyPurpose = keyof typeof KEY_INFO;

// A fixed, non-secret salt. HKDF with a constant salt still yields independent
// keys per `info`; the separation we need comes from the distinct info labels.
const HKDF_SALT = Buffer.from('threshold-hkdf-salt:v1', 'utf8');

/** Derive a 32-byte key for a purpose from the root secret (MED-33). */
export function deriveKey(secret: string, purpose: KeyPurpose): Buffer {
  const info = Buffer.from(KEY_INFO[purpose], 'utf8');
  const derived = hkdfSync('sha256', Buffer.from(secret, 'utf8'), HKDF_SALT, info, 32);
  return Buffer.from(derived);
}
