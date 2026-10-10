import { describe, it, expect } from 'vitest';
import { RingGateway } from '../../src/services/ring-gateway.js';
import { FixtureRing } from '../../src/services/fixtures/fixture-ring.js';
import { TokenBucket } from '../../src/services/rate-limiter.js';

const noSleep = async () => {};
const fixedRandom = () => 0; // zero jitter for deterministic timing

describe('RingGateway (FR-2.3, FR-17, NFR-7, design.md §6)', () => {
  it('returns devices on the happy path', async () => {
    const ring = new FixtureRing();
    const gw = new RingGateway(ring, { sleep: noSleep, random: fixedRandom });
    const devices = await gw.listDevices('resident-x', 'access');
    expect(devices).toHaveLength(2);
  });

  it('retries 5xx at most twice then succeeds', async () => {
    const ring = new FixtureRing();
    ring.failTransiently(2, 'ring_unavailable');
    const gw = new RingGateway(ring, { sleep: noSleep, random: fixedRandom });
    const devices = await gw.listDevices('resident-x', 'access');
    expect(devices).toHaveLength(2);
    expect(ring.listDevicesInvocations).toBe(3); // 1 + 2 retries
  });

  it('gives up with ring_unavailable after exhausting 5xx retries', async () => {
    const ring = new FixtureRing();
    ring.failTransiently(5, 'ring_unavailable');
    const gw = new RingGateway(ring, { sleep: noSleep, random: fixedRandom });
    await expect(gw.listDevices('resident-x', 'access')).rejects.toMatchObject({ code: 'ring_unavailable' });
  });

  it('backs off and retries on 429, then succeeds', async () => {
    const ring = new FixtureRing();
    ring.failTransiently(1, 'rate_limited');
    const gw = new RingGateway(ring, { sleep: noSleep, random: fixedRandom });
    const devices = await gw.listDevices('resident-x', 'access');
    expect(devices).toHaveLength(2);
  });

  it('surfaces rate_limited after exhausting 429 retries', async () => {
    const ring = new FixtureRing();
    ring.failTransiently(5, 'rate_limited');
    const gw = new RingGateway(ring, { sleep: noSleep, random: fixedRandom });
    await expect(gw.listDevices('resident-x', 'access')).rejects.toMatchObject({ code: 'rate_limited' });
  });

  it('propagates ring_contract_invalid immediately without retrying (FR-17)', async () => {
    const ring = new FixtureRing();
    ring.setMalformedDevices();
    const gw = new RingGateway(ring, { sleep: noSleep, random: fixedRandom });
    await expect(gw.listDevices('resident-x', 'access')).rejects.toMatchObject({
      code: 'ring_contract_invalid',
    });
    expect(ring.listDevicesInvocations).toBe(1);
  });

  it('rate_limited immediately when the local bucket is exhausted (never exceed 100 rps)', async () => {
    const ring = new FixtureRing();
    const t = 0;
    const bucket = new TokenBucket({ capacity: 1, refillPerSecond: 1, now: () => t });
    const gw = new RingGateway(ring, { bucket, sleep: noSleep, random: fixedRandom });
    await gw.listDevices('resident-x', 'access'); // consumes the only token
    await expect(gw.listDevices('resident-x', 'access')).rejects.toMatchObject({ code: 'rate_limited' });
  });

  it('takes a token per ATTEMPT, not per call (MED-30)', async () => {
    const ring = new FixtureRing();
    ring.failTransiently(2, 'ring_unavailable'); // forces 3 attempts (1 + 2 retries)
    const t = 0;
    // A global bucket with exactly 2 tokens cannot cover 3 attempts, so the
    // third attempt is throttled: a retry no longer buys a free upstream call.
    const bucket = new TokenBucket({ capacity: 2, refillPerSecond: 1, now: () => t });
    const gw = new RingGateway(ring, {
      bucket,
      sleep: noSleep,
      random: fixedRandom,
      perResidentCapacity: 100,
      perResidentRefillPerSecond: 100,
    });
    await expect(gw.listDevices('resident-x', 'access')).rejects.toMatchObject({
      code: 'rate_limited',
    });
    // Only two upstream attempts were made before the bucket ran dry.
    expect(ring.listDevicesInvocations).toBe(2);
  });

  it('isolates residents with per-resident fairness (MED-30)', async () => {
    const ring = new FixtureRing();
    const t = 0;
    // A large global bucket, but a per-resident cap of 1: one resident spending
    // their token must not starve another resident.
    const bucket = new TokenBucket({ capacity: 100, refillPerSecond: 100, now: () => t });
    const gw = new RingGateway(ring, {
      bucket,
      sleep: noSleep,
      random: fixedRandom,
      perResidentCapacity: 1,
      perResidentRefillPerSecond: 1,
      now: () => t,
    });
    await gw.listDevices('resident-a', 'access'); // resident A spends their token
    // Resident A is now throttled...
    await expect(gw.listDevices('resident-a', 'access')).rejects.toMatchObject({
      code: 'rate_limited',
    });
    // ...but resident B is unaffected and still gets served.
    const devicesB = await gw.listDevices('resident-b', 'access');
    expect(devicesB).toHaveLength(2);
  });
});
