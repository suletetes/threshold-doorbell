import { describe, it, expect } from 'vitest';
import { FixtureRing, fixtureResidentSub } from '../../src/services/fixtures/fixture-ring.js';
import { AppError } from '../../src/domain/errors.js';

describe('FixtureRing (schema-validating adapter, FR-17)', () => {
  it('lists golden devices through the schema layer', async () => {
    const ring = new FixtureRing();
    const devices = await ring.listDevices('access');
    expect(devices).toHaveLength(2);
    expect(devices[0]!.id).toBe('ring-doorbell-001');
    expect(devices[0]!.capabilities).toContain('two_way_talk');
    expect(devices[1]!.privacyZones).toHaveLength(1);
  });

  it('returns an empty list for the empty-devices case (FR-2.2)', async () => {
    const ring = new FixtureRing();
    ring.setEmptyDevices();
    expect(await ring.listDevices('access')).toEqual([]);
  });

  it('raises ring_contract_invalid on malformed payload (AT-23)', async () => {
    const ring = new FixtureRing();
    ring.setMalformedDevices();
    await expect(ring.listDevices('access')).rejects.toBeInstanceOf(AppError);
    await ring.listDevices('access').catch((e: AppError) => {
      expect(e.code).toBe('ring_contract_invalid');
    });
  });

  it('exchanges a code for tokens with an opaque identity (FR-1.2, CRIT-03, LOW-41)', async () => {
    const ring = new FixtureRing();
    const tokens = await ring.exchangeCode('auth-code', 'verifier', 'redirect');
    // Identity is a one-way function of the account seed, never `resident-<code>`.
    expect(tokens.residentSub).toBe(fixtureResidentSub('auth-code'));
    expect(tokens.residentSub).not.toBe('resident-auth-code');
    // The access/refresh token strings do NOT carry the raw code, so identity
    // cannot be reconstructed from the token text.
    expect(tokens.accessToken).not.toContain('auth-code');
    expect(tokens.refreshToken).not.toContain('auth-code');
  });

  it('keeps the same identity across a refresh (CRIT-03)', async () => {
    const ring = new FixtureRing();
    const tokens = await ring.exchangeCode('auth-code', 'verifier', 'redirect');
    const refreshed = await ring.refresh(tokens.refreshToken);
    expect(refreshed.residentSub).toBe(tokens.residentSub);
    // A fresh, opaque access token is issued; it is not the previous one.
    expect(refreshed.accessToken).not.toBe(tokens.accessToken);
    expect(refreshed.accessToken).toMatch(/^access-/);
  });

  it('mints distinct identities for distinct accounts (no collision, P2-2)', async () => {
    const ring = new FixtureRing();
    const a = await ring.exchangeCode('account-42', 'v', 'r');
    const b = await ring.exchangeCode('refresh-account-42', 'v', 'r');
    expect(a.residentSub).not.toBe(b.residentSub);
  });

  it('fails exchange and refresh when configured to (FR-1.5)', async () => {
    const ring = new FixtureRing();
    ring.failExchange();
    await expect(ring.exchangeCode('x', 'v', 'r')).rejects.toBeInstanceOf(AppError);
    ring.failRefresh();
    await expect(ring.refresh('rt')).rejects.toBeInstanceOf(AppError);
  });
});
