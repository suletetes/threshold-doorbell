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

  it('forces a refresh when expiresAt is unparseable (L-4)', async () => {
    const { ring, svc } = build();
    // Persist a record whose expiry cannot be parsed. The refresh token is
    // encrypted by the service so the forced refresh path can decrypt it.
    await svc.persist('resident-a', {
      accessToken: 'stale-access',
      refreshToken: 'plain-refresh',
      expiresAt: 'not-a-date',
    });
    const token = await svc.getAccessToken('resident-a');
    // A refresh issues a fresh, opaque access token, not the stored stale one.
    expect(token).toMatch(/^access-/);
    expect(token).not.toBe('stale-access');
    expect(ring.refreshInvocations).toBe(1);
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

  it('maps a decrypt failure on the access token to refresh_failed, not a 500 (MED-31)', async () => {
    const { store, svc } = build();
    // Store a record whose ciphertext cannot be decrypted (not near expiry so
    // the non-refresh decrypt path runs).
    await store.put({
      residentSub: 'resident-a',
      accessTokenEnc: 'not-valid-ciphertext',
      refreshTokenEnc: 'not-valid-ciphertext',
      expiresAt: new Date(Date.now() + 3600_000).toISOString(),
    });
    await expect(svc.getAccessToken('resident-a')).rejects.toMatchObject({
      code: 'refresh_failed',
    });
  });

  it('coalesces concurrent refreshes per resident into one (MED-31 single-flight)', async () => {
    const { ring, svc } = build();
    await svc.persist('resident-a', {
      accessToken: 'plain-access',
      refreshToken: 'plain-refresh',
      expiresAt: new Date(Date.now() + 60_000).toISOString(), // within skew -> refresh
    });
    // Fire several concurrent getAccessToken calls; only one upstream refresh
    // should occur, so a token rotation cannot log the others out.
    const results = await Promise.all([
      svc.getAccessToken('resident-a'),
      svc.getAccessToken('resident-a'),
      svc.getAccessToken('resident-a'),
    ]);
    expect(new Set(results).size).toBe(1); // all callers get the same fresh token
    expect(ring.refreshInvocations).toBe(1);
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
