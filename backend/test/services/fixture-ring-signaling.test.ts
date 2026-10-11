import { describe, it, expect } from 'vitest';
import {
  FIXTURE_SDP_ANSWER,
  FixtureRingSignaling,
} from '../../src/services/fixtures/fixture-ring-signaling.js';

describe('FixtureRingSignaling (Task 7, FR-4.1; AT-3)', () => {
  it('returns the canned SDP answer with the AT-3 media shape', async () => {
    const s = new FixtureRingSignaling();
    const handle = await s.startSession({ sdpOffer: 'v=0', deviceId: 'dev-1', accessToken: 'a' });
    expect(handle.sdpAnswer).toBe(FIXTURE_SDP_ANSWER);
    expect(handle.sdpAnswer).toContain('a=sendrecv'); // audio two-way
    expect(handle.sdpAnswer).toContain('a=recvonly'); // video inbound only
    expect(handle.sessionUrl).toContain('dev-1');
  });

  it('issues a unique session URL per session', async () => {
    const s = new FixtureRingSignaling();
    const a = await s.startSession({ sdpOffer: 'o', deviceId: 'dev', accessToken: 'a' });
    const b = await s.startSession({ sdpOffer: 'o', deviceId: 'dev', accessToken: 'a' });
    expect(a.sessionUrl).not.toBe(b.sessionUrl);
    expect(s.issuedUrls()).toEqual([a.sessionUrl, b.sessionUrl]);
  });

  it('records released URLs and release is idempotent (FR-4.3)', async () => {
    const s = new FixtureRingSignaling();
    const { sessionUrl } = await s.startSession({ sdpOffer: 'o', deviceId: 'dev', accessToken: 'a' });
    await s.releaseSession(sessionUrl);
    await s.releaseSession(sessionUrl); // no throw on repeat
    expect(s.wasReleased(sessionUrl)).toBe(true);
    expect(s.releasedUrls()).toEqual([sessionUrl]);
  });

  it('rejects an empty offer (contract violation)', async () => {
    const s = new FixtureRingSignaling();
    await expect(s.startSession({ sdpOffer: '', deviceId: 'dev', accessToken: 'a' })).rejects.toThrow();
  });

  it('rejects when error mode is set (connect failure path)', async () => {
    const s = new FixtureRingSignaling();
    s.setError();
    await expect(s.startSession({ sdpOffer: 'o', deviceId: 'dev', accessToken: 'a' })).rejects.toThrow();
    s.setOk();
    await expect(s.startSession({ sdpOffer: 'o', deviceId: 'dev', accessToken: 'a' })).resolves.toBeTruthy();
  });
});
