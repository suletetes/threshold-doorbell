// Local AES-256-GCM envelope crypto (fixture for CryptoPort). Runs without AWS.
// Ciphertext format: base64url(version(1) | iv(12) | authTag(16) | ciphertext).
// Used in "local"/"demo" environments and in all tests (Task 4, FR-1.6).

import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';
import type { CryptoPort } from '../crypto.js';

const VERSION = 0x01;
const IV_LEN = 12;
const TAG_LEN = 16;

export class LocalCrypto implements CryptoPort {
  private readonly key: Buffer;

  /**
   * Derive a stable 32-byte key from a secret string. In local/demo this is the
   * session/app secret; it never leaves the process and never touches storage.
   */
  constructor(secret: string) {
    if (!secret || secret.length < 8) {
      throw new Error('LocalCrypto requires a secret of at least 8 characters');
    }
    this.key = createHash('sha256').update(secret, 'utf8').digest();
  }

  async encrypt(plaintext: string): Promise<string> {
    const iv = randomBytes(IV_LEN);
    const cipher = createCipheriv('aes-256-gcm', this.key, iv);
    const enc = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
    const tag = cipher.getAuthTag();
    return Buffer.concat([Buffer.from([VERSION]), iv, tag, enc]).toString('base64url');
  }

  async decrypt(ciphertext: string): Promise<string> {
    let buf: Buffer;
    try {
      buf = Buffer.from(ciphertext, 'base64url');
    } catch {
      throw new Error('invalid ciphertext encoding');
    }
    if (buf.length < 1 + IV_LEN + TAG_LEN) {
      throw new Error('ciphertext too short');
    }
    if (buf[0] !== VERSION) {
      throw new Error('unsupported ciphertext version');
    }
    const iv = buf.subarray(1, 1 + IV_LEN);
    const tag = buf.subarray(1 + IV_LEN, 1 + IV_LEN + TAG_LEN);
    const enc = buf.subarray(1 + IV_LEN + TAG_LEN);
    const decipher = createDecipheriv('aes-256-gcm', this.key, iv);
    decipher.setAuthTag(tag);
    // Throws on auth-tag mismatch (tamper detection).
    return Buffer.concat([decipher.update(enc), decipher.final()]).toString('utf8');
  }
}
