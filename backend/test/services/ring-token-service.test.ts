import { describe, it, expect } from 'vitest';
import { RingTokenService } from '../../src/services/ring-token-service.js';
import { FixtureRing } from '../../src/services/fixtures/fixture-ring.js';
import { MemoryTokenStore } from '../../src/services/fixtures/memory-stores.js';
import { LocalCrypto } from '../../src/services/fixtures/local-crypto.js';
import { AppError } from '../../src/domain/errors.js';

function build() {
  const ring = new FixtureRing();
  const store = new MemoryTokenStore();
  const crypto = new LocalCrypto('a-sufficiently-long-secret');
  const svc = new RingTokenService(ring, store, crypto);
  return { ring, store, crypto, svc };
}

describe('RingTokenService', () => {
  it('persists tokens encrypted at rest, never in cleartext (FR-1.6)', async () => {
    const { store, svc } = build();
    await svc.persist('resident-a', {
      accessToken: 'plain-access',
      refreshToken: 'plain-refresh',
      expiresAt: new Date(Date.now() + 3600_000).toISOString(),
    });
    const row = await store.get('resident-a');
    expect(row).not.toBeNull();
    expect(row!.accessTokenEnc).not.toContain('plain-access');
    expect(row!.refreshTokenEnc).not.toContain('plain-refresh');
    // Serialized record contains no cleartext token (device never sees tokens).
    expect(JSON.stringify(row)).not.toContain('plain-access');
    expect(JSON.stringify(row)).not.toContain('plain-refresh');
  });

  it('returns a decrypted access token when not near expiry', async () => {
    const { svc } = build();
    await svc.persist('resident-a', {
      accessToken: 'plain-access',
      refreshToken: 'plain-refresh',
      expiresAt: new Date(Date.now() + 3600_000).toISOString(),
    });
    expect(await svc.getAccessToken('resident-a')).toBe('plain-access');
  });

  it('refreshes proactively within the 120s skew (FR-1.4)', async () => {
    const { ring, svc } = build();
    await svc.persist('resident-a', {
      accessToken: 'plain-access',
      refreshToken: 'plain-refresh',
      expiresAt: new Date(Date.now() + 60_000).toISOString(), // within skew
    });
    const token = await svc.getAccessToken('resident-a');
    // A refresh issues a fresh, opaque access token distinct from the old one.
    expect(token).toMatch(/^access-/);
    expect(token).not.toBe('plain-access');
    expect(ring.refreshInvocations).toBe(1);
  });

  it('refreshes exactly once and retries once on a 401 (AT-1, FR-1.4)', async () => {
    const { ring, svc } = build();
    ring.requireRefreshOn401();
    await svc.persist('resident-a', {
      accessToken: 'plain-access',
      refreshToken: 'plain-refresh',
      expiresAt: new Date(Date.now() + 3600_000).toISOString(),
    });
    const devices = await svc.withAccessToken('resident-a', (t) => ring.listDevices(t));
    expect(devices).toHaveLength(2);
    // Exactly one refresh occurred.
    expect(ring.refreshInvocations).toBe(1);
  });

  it('surfaces refresh_failed when refresh fails (unified recovery, FR-1.5)', async () => {
    const { ring, svc } = build();
    await svc.persist('resident-a', {
      accessToken: 'plain-access',
      refreshToken: 'plain-refresh',
      expiresAt: new Date(Date.now() + 60_000).toISOString(),
    });
    ring.failRefresh();
    await expect(svc.getAccessToken('resident-a')).rejects.toMatchObject({
      code: 'refresh_failed',
    });
  });

  it('surfaces refresh_failed when no token record exists', async () => {
    const { svc } = build();
    await expect(svc.getAccessToken('unknown')).rejects.toBeInstanceOf(AppError);
  });

  it('revoke removes the stored token row (FR-8.6)', async () => {
    const { store, svc } = build();
    await svc.persist('resident-a', {
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: new Date(Date.now() + 3600_000).toISOString(),
    });
    await svc.revoke('resident-a');
    expect(await store.get('resident-a')).toBeNull();
  });

  it('does not refresh a second time when the retried call still fails non-401', async () => {
    const { ring, svc } = build();
    await svc.persist('resident-a', {
      accessToken: 'plain-access',
      refreshToken: 'plain-refresh',
      expiresAt: new Date(Date.now() + 3600_000).toISOString(),
    });
    ring.setMalformedDevices();
    await expect(
      svc.withAccessToken('resident-a', (t) => ring.listDevices(t)),
    ).rejects.toMatchObject({ code: 'ring_contract_invalid' });
    // A schema error is not a 401, so no refresh should have happened.
    expect(ring.refreshInvocations).toBe(0);
  });
});
