// Envelope-encryption port (Task 4, FR-1.6). The real adapter wraps AWS KMS;
// the fixture uses local AES-256-GCM so token storage runs without AWS.
//
// The interface is deliberately KMS-shaped: encrypt/decrypt of opaque plaintext
// to/from a self-describing ciphertext string. Callers never see key material.

export interface CryptoPort {
  /** Encrypt UTF-8 plaintext, returning an opaque ciphertext string. */
  encrypt(plaintext: string): Promise<string>;
  /** Decrypt a ciphertext produced by encrypt(). Throws on tamper/format error. */
  decrypt(ciphertext: string): Promise<string>;
}
