import { describe, it, expect } from 'vitest';
import { LocalCrypto } from '../../src/services/fixtures/local-crypto.js';

describe('LocalCrypto (fixture CryptoPort)', () => {
  it('round-trips plaintext', async () => {
    const c = new LocalCrypto('a-sufficiently-long-secret');
    const ct = await c.encrypt('ring-access-token-value');
    expect(ct).not.toContain('ring-access-token-value');
    const pt = await c.decrypt(ct);
    expect(pt).toBe('ring-access-token-value');
  });

  it('produces different ciphertext for the same plaintext (random IV)', async () => {
    const c = new LocalCrypto('a-sufficiently-long-secret');
    const a = await c.encrypt('same');
    const b = await c.encrypt('same');
    expect(a).not.toBe(b);
    expect(await c.decrypt(a)).toBe('same');
    expect(await c.decrypt(b)).toBe('same');
  });

  it('rejects a secret that is too short', () => {
    expect(() => new LocalCrypto('short')).toThrow();
  });

  it('detects tampering via the auth tag', async () => {
    const c = new LocalCrypto('a-sufficiently-long-secret');
    const ct = await c.encrypt('secret');
    // Flip a character in the ciphertext body.
    const tampered = ct.slice(0, -2) + (ct.slice(-2) === 'AA' ? 'BB' : 'AA');
    await expect(c.decrypt(tampered)).rejects.toThrow();
  });

  it('rejects a wrong-key decrypt', async () => {
    const a = new LocalCrypto('secret-number-one');
    const b = new LocalCrypto('secret-number-two');
    const ct = await a.encrypt('payload');
    await expect(b.decrypt(ct)).rejects.toThrow();
  });

  it('rejects malformed ciphertext', async () => {
    const c = new LocalCrypto('a-sufficiently-long-secret');
    await expect(c.decrypt('!!!not-base64!!!')).rejects.toThrow();
    await expect(c.decrypt('AA')).rejects.toThrow();
  });
});
