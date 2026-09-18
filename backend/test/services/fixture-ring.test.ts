import { describe, it, expect } from 'vitest';
import { FixtureRing } from '../../src/services/fixtures/fixture-ring.js';
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

  it('exchanges a code for tokens and refreshes them (FR-1.2, FR-1.4)', async () => {
    const ring = new FixtureRing();
    const tokens = await ring.exchangeCode('auth-code', 'verifier', 'redirect');
    expect(tokens.accessToken).toBe('access-auth-code');
    expect(tokens.refreshToken).toBe('refresh-auth-code');
    const refreshed = await ring.refresh(tokens.refreshToken);
    expect(refreshed.accessToken).toContain('access-refreshed');
  });

  it('fails exchange and refresh when configured to (FR-1.5)', async () => {
    const ring = new FixtureRing();
    ring.failExchange();
    await expect(ring.exchangeCode('x', 'v', 'r')).rejects.toBeInstanceOf(AppError);
    ring.failRefresh();
    await expect(ring.refresh('rt')).rejects.toBeInstanceOf(AppError);
  });
});
