import { describe, it, expect } from 'vitest';
import { computeSignature, verifySignature } from '../../src/security/hmac.js';

const KEY = 'webhook-key';

describe('HMAC webhook verification (FR-3.1)', () => {
  it('verifies a correct signature', () => {
    const body = '{"request_id":"r1"}';
    const sig = computeSignature(body, KEY);
    expect(verifySignature(body, sig, KEY)).toBe(true);
  });

  it('accepts a sha256= prefixed signature', () => {
    const body = '{"request_id":"r1"}';
    const sig = computeSignature(body, KEY);
    expect(verifySignature(body, `sha256=${sig}`, KEY)).toBe(true);
  });

  it('rejects a wrong signature', () => {
    const body = '{"request_id":"r1"}';
    expect(verifySignature(body, computeSignature(body, 'other-key'), KEY)).toBe(false);
  });

  it('rejects when the body was altered', () => {
    const sig = computeSignature('{"request_id":"r1"}', KEY);
    expect(verifySignature('{"request_id":"r2"}', sig, KEY)).toBe(false);
  });

  it('rejects missing, empty, and short signatures without throwing', () => {
    const body = 'x';
    expect(verifySignature(body, undefined, KEY)).toBe(false);
    expect(verifySignature(body, '', KEY)).toBe(false);
    expect(verifySignature(body, 'abc', KEY)).toBe(false);
  });
});
