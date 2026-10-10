// MED-31 regression: the Ring token response schema must validate expires_in so
// a huge or negative value cannot produce an out-of-range Date (RangeError) that
// surfaces as an unlogged 500, nor mint an already-expired token.

import { describe, it, expect } from 'vitest';
import { parseTokenResponse } from '../../src/services/ring-schema.js';

const base = { access_token: 'at', refresh_token: 'rt' };

describe('parseTokenResponse (MED-31, FR-17)', () => {
  it('accepts a normal expires_in and stamps a future expiry', () => {
    const parsed = parseTokenResponse({ ...base, expires_in: 3600 });
    expect(parsed.accessToken).toBe('at');
    expect(parsed.refreshToken).toBe('rt');
    expect(Date.parse(parsed.expiresAt)).toBeGreaterThan(Date.now());
  });

  it('defaults to one hour when expires_in is absent', () => {
    const parsed = parseTokenResponse({ ...base });
    const seconds = Math.round((Date.parse(parsed.expiresAt) - Date.now()) / 1000);
    expect(seconds).toBeGreaterThan(3000);
    expect(seconds).toBeLessThanOrEqual(3600);
  });

  it('rejects an absurd expires_in instead of throwing RangeError', () => {
    expect(() => parseTokenResponse({ ...base, expires_in: 1e300 })).toThrowError(
      expect.objectContaining({ code: 'code_exchange_failed' }),
    );
  });

  it('rejects a negative expires_in instead of minting an expired token', () => {
    expect(() => parseTokenResponse({ ...base, expires_in: -1 })).toThrowError(
      expect.objectContaining({ code: 'code_exchange_failed' }),
    );
  });

  it('rejects a non-finite expires_in', () => {
    expect(() => parseTokenResponse({ ...base, expires_in: Infinity })).toThrowError(
      expect.objectContaining({ code: 'code_exchange_failed' }),
    );
  });
});
