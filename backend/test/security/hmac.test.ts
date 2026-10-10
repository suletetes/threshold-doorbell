import { describe, it, expect } from 'vitest';
import {
  computeSignature,
  computeTimestampedSignature,
  verifySignature,
  verifyTimestampedSignature,
} from '../../src/security/hmac.js';

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

describe('timestamped HMAC verification with replay window + key list (MED-38)', () => {
  const now = Date.parse('2026-01-01T00:00:00.000Z');
  const body = '{"request_id":"r1"}';

  it('verifies a signature over timestamp.body within the window', () => {
    const ts = new Date(now).toISOString();
    const sig = computeTimestampedSignature(ts, body, KEY);
    expect(
      verifyTimestampedSignature({ timestamp: ts, rawBody: body, providedSignature: sig, keys: [KEY], now }),
    ).toBe(true);
  });

  it('rejects a stale timestamp outside the +/-5 minute window', () => {
    const staleTs = new Date(now - 6 * 60 * 1000).toISOString();
    const sig = computeTimestampedSignature(staleTs, body, KEY);
    expect(
      verifyTimestampedSignature({ timestamp: staleTs, rawBody: body, providedSignature: sig, keys: [KEY], now }),
    ).toBe(false);
  });

  it('rejects a body replayed under a fresh timestamp (signature bound to ts)', () => {
    const ts1 = new Date(now).toISOString();
    const sig = computeTimestampedSignature(ts1, body, KEY);
    const freshTs = new Date(now + 1000).toISOString();
    // Reusing sig with a different timestamp must fail (the ts is signed).
    expect(
      verifyTimestampedSignature({ timestamp: freshTs, rawBody: body, providedSignature: sig, keys: [KEY], now }),
    ).toBe(false);
  });

  it('accepts a signature from any key in the rotation list', () => {
    const ts = new Date(now).toISOString();
    const sig = computeTimestampedSignature(ts, body, 'new-key');
    expect(
      verifyTimestampedSignature({
        timestamp: ts,
        rawBody: body,
        providedSignature: sig,
        keys: ['old-key', 'new-key'],
        now,
      }),
    ).toBe(true);
  });

  it('rejects a missing timestamp or signature', () => {
    const ts = new Date(now).toISOString();
    const sig = computeTimestampedSignature(ts, body, KEY);
    expect(
      verifyTimestampedSignature({ timestamp: undefined, rawBody: body, providedSignature: sig, keys: [KEY], now }),
    ).toBe(false);
    expect(
      verifyTimestampedSignature({ timestamp: ts, rawBody: body, providedSignature: undefined, keys: [KEY], now }),
    ).toBe(false);
  });
});
