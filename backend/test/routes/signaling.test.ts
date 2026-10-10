import { describe, it, expect, afterEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildTestApp, sessionFor } from '../helpers/test-app.js';
import { collectUntilClose, nextJson, waitFor } from '../helpers/ws.js';
import { SIGNALING_CLOSE } from '../../src/routes/signaling.js';
import { FIXTURE_SDP_ANSWER } from '../../src/services/fixtures/fixture-ring-signaling.js';

let app: FastifyInstance | undefined;
afterEach(async () => {
  if (app) await app.close();
  app = undefined;
});

const SUB = 'resident-signaling';
const DEVICE = 'ring-front-door';

/**
 * Authorize a resident for a device: persist a Ring token (so withAccessToken
 * can vend one) and map the device to the resident (HIGH-20 ownership check).
 */
async function authorize(
  t: Awaited<ReturnType<typeof buildTestApp>>,
  sub: string,
  deviceId = DEVICE,
): Promise<void> {
  await t.container.ringTokens.persist(sub, {
    accessToken: 'a',
    refreshToken: 'r',
    expiresAt: new Date(Date.now() + 3600_000).toISOString(),
  });
  await t.deviceAccountStore.map(deviceId, sub);
}

function offer(deviceId = DEVICE): string {
  return JSON.stringify({
    type: 'offer',
    deviceId,
    // A minimal WHEP offer: audio sendrecv, video recvonly (AT-3 shape).
    sdp: ['v=0', 'm=audio 9 UDP/TLS/RTP/SAVPF 111', 'a=sendrecv', 'm=video 9 UDP/TLS/RTP/SAVPF 96', 'a=recvonly'].join('\r\n'),
  });
}

describe('WS /signaling (Task 7, FR-4.1, 4.6, 4.7; AT-3, AT-11)', () => {
  it('closes 4401 when no session credential is supplied', async () => {
    const t = await buildTestApp();
    app = t.app;
    const ws = await app.injectWS('/signaling');
    const { frames, code } = await collectUntilClose(ws);
    expect(code).toBe(SIGNALING_CLOSE.unauthorized);
    expect(frames[0]).toMatchObject({ type: 'error', code: 'unauthorized' });
  });

  it('relays a WHEP offer to a canned SDP answer and session URL (AT-3)', async () => {
    const t = await buildTestApp();
    app = t.app;
    await authorize(t, SUB);
    const token = sessionFor(SUB, t.config.sessionSecret);
    const ws = await app.injectWS(`/signaling?token=${encodeURIComponent(token)}`);
    ws.send(offer());
    const answer = await nextJson(ws);
    expect(answer).toMatchObject({ type: 'answer', sdpAnswer: FIXTURE_SDP_ANSWER });
    expect(String((answer as { sessionUrl: string }).sessionUrl)).toContain('fixture.ring.local');
    // The AT-3 shape: audio sendrecv, video recvonly.
    expect(FIXTURE_SDP_ANSWER).toContain('a=sendrecv');
    expect(FIXTURE_SDP_ANSWER).toContain('a=recvonly');
    ws.close();
  });

  it('authenticates via the session cookie as well as the token query', async () => {
    const t = await buildTestApp();
    app = t.app;
    await authorize(t, SUB);
    const token = sessionFor(SUB, t.config.sessionSecret);
    const ws = await app.injectWS('/signaling', {
      headers: { cookie: `threshold_session=${token}` },
    });
    ws.send(offer());
    const answer = await nextJson(ws);
    expect(answer).toMatchObject({ type: 'answer' });
    ws.close();
  });

  it('rejects a second concurrent session with close code 4409 and keeps the first (FR-4.7, AT-11)', async () => {
    const t = await buildTestApp();
    app = t.app;
    await authorize(t, SUB);
    const token = sessionFor(SUB, t.config.sessionSecret);

    const first = await app.injectWS(`/signaling?token=${encodeURIComponent(token)}`);
    first.send(offer());
    const firstAnswer = await nextJson(first);
    expect(firstAnswer).toMatchObject({ type: 'answer' });
    expect(t.signalingService.hasActiveSession(SUB)).toBe(true);

    // A second socket for the SAME resident tries to open a session.
    const second = await app.injectWS(`/signaling?token=${encodeURIComponent(token)}`);
    second.send(offer('ring-back-door'));
    const { frames, code } = await collectUntilClose(second);
    expect(code).toBe(SIGNALING_CLOSE.sessionAlreadyActive);
    expect(frames[0]).toMatchObject({ type: 'error', code: 'session_already_active' });

    // The incumbent session is untouched and still exactly one exists.
    expect(t.signalingService.hasActiveSession(SUB)).toBe(true);
    const firstUrl = t.signalingService.activeSessionUrl(SUB);
    expect(t.ringSignaling.issuedUrls()).toContain(firstUrl);
    first.close();
  });

  it('releases the Ring session URL when the socket closes (FR-4.3)', async () => {
    const t = await buildTestApp();
    app = t.app;
    await authorize(t, SUB);
    const token = sessionFor(SUB, t.config.sessionSecret);
    const ws = await app.injectWS(`/signaling?token=${encodeURIComponent(token)}`);
    ws.send(offer());
    const answer = await nextJson<{ sessionUrl: string }>(ws);
    const url = answer.sessionUrl;

    ws.terminate();
    await waitFor(() => t.ringSignaling.wasReleased(url));
    expect(t.ringSignaling.wasReleased(url)).toBe(true);
    expect(t.signalingService.hasActiveSession(SUB)).toBe(false);
  });

  it('an explicit end frame releases the session and closes normally (FR-4.3)', async () => {
    const t = await buildTestApp();
    app = t.app;
    await authorize(t, SUB);
    const token = sessionFor(SUB, t.config.sessionSecret);
    const ws = await app.injectWS(`/signaling?token=${encodeURIComponent(token)}`);
    ws.send(offer());
    const answer = await nextJson<{ sessionUrl: string }>(ws);
    const url = answer.sessionUrl;
    ws.send(JSON.stringify({ type: 'end' }));
    await new Promise<void>((resolve) => ws.on('close', () => resolve()));
    await new Promise((r) => setTimeout(r, 20));
    expect(t.ringSignaling.wasReleased(url)).toBe(true);
    expect(t.signalingService.hasActiveSession(SUB)).toBe(false);
  });

  it('after a session ends, a new session for the same resident can open (single-slot reuse)', async () => {
    const t = await buildTestApp();
    app = t.app;
    await authorize(t, SUB);
    const token = sessionFor(SUB, t.config.sessionSecret);

    const a = await app.injectWS(`/signaling?token=${encodeURIComponent(token)}`);
    a.send(offer());
    await nextJson(a);
    a.terminate();
    await waitFor(() => !t.signalingService.hasActiveSession(SUB));
    expect(t.signalingService.hasActiveSession(SUB)).toBe(false);

    const b = await app.injectWS(`/signaling?token=${encodeURIComponent(token)}`);
    b.send(offer());
    const answerB = await nextJson(b);
    expect(answerB).toMatchObject({ type: 'answer' });
    b.close();
  });

  it('releases the slot when the socket disconnects during the Ring handshake (HIGH-19, P3)', async () => {
    const t = await buildTestApp();
    app = t.app;
    await authorize(t, SUB);
    const token = sessionFor(SUB, t.config.sessionSecret);
    // Make the Ring handshake slow so we can disconnect while open() is pending.
    t.ringSignaling.setStartDelay(80);

    const first = await app.injectWS(`/signaling?token=${encodeURIComponent(token)}`);
    first.send(offer());
    // Terminate before the delayed startSession resolves (mid-handshake).
    first.terminate();

    // The slot must be released once the pending open settles; it must NOT stay
    // reserved and lock the resident out.
    await waitFor(() => !t.signalingService.hasActiveSession(SUB));
    expect(t.signalingService.hasActiveSession(SUB)).toBe(false);

    // A fresh attempt for the same resident must succeed, not be closed 4409.
    t.ringSignaling.setStartDelay(0);
    const second = await app.injectWS(`/signaling?token=${encodeURIComponent(token)}`);
    second.send(offer());
    const answer = await nextJson(second);
    expect(answer).toMatchObject({ type: 'answer' });
    second.close();
  });

  it('a Ring relay failure surfaces a connect error and frees the slot for retry (FR-4.4)', async () => {
    const t = await buildTestApp();
    app = t.app;
    await authorize(t, SUB);
    t.ringSignaling.setError();
    const token = sessionFor(SUB, t.config.sessionSecret);
    const ws = await app.injectWS(`/signaling?token=${encodeURIComponent(token)}`);
    ws.send(offer());
    const { frames } = await collectUntilClose(ws);
    expect(frames[0]).toMatchObject({ type: 'error', code: 'ring_unavailable' });
    expect(t.signalingService.hasActiveSession(SUB)).toBe(false);
  });

  it('rejects a session for a device the resident does not own (HIGH-20)', async () => {
    const t = await buildTestApp();
    app = t.app;
    // The resident is authorized for DEVICE but requests someone else's device.
    await authorize(t, SUB);
    await t.deviceAccountStore.map('someone-elses-device', 'resident-other');
    const token = sessionFor(SUB, t.config.sessionSecret);
    const ws = await app.injectWS(`/signaling?token=${encodeURIComponent(token)}`);
    ws.send(offer('someone-elses-device'));
    const { frames, code } = await collectUntilClose(ws);
    expect(code).toBe(SIGNALING_CLOSE.unauthorized);
    expect(frames[0]).toMatchObject({ type: 'error', code: 'unauthorized' });
    // No session was opened and no Ring URL was issued for the foreign device.
    expect(t.signalingService.hasActiveSession(SUB)).toBe(false);
    expect(t.ringSignaling.issuedUrls()).toHaveLength(0);
  });

  it('rejects a session for an unmapped device (HIGH-20)', async () => {
    const t = await buildTestApp();
    app = t.app;
    await authorize(t, SUB);
    const token = sessionFor(SUB, t.config.sessionSecret);
    const ws = await app.injectWS(`/signaling?token=${encodeURIComponent(token)}`);
    ws.send(offer('never-registered'));
    const { code } = await collectUntilClose(ws);
    expect(code).toBe(SIGNALING_CLOSE.unauthorized);
    expect(t.signalingService.hasActiveSession(SUB)).toBe(false);
  });

  it('two different residents each hold their own single session concurrently', async () => {
    const t = await buildTestApp();
    app = t.app;
    await authorize(t, 'resident-a', 'device-a');
    await authorize(t, 'resident-b', 'device-b');
    const tokenA = sessionFor('resident-a', t.config.sessionSecret);
    const tokenB = sessionFor('resident-b', t.config.sessionSecret);
    const a = await app.injectWS(`/signaling?token=${encodeURIComponent(tokenA)}`);
    a.send(offer('device-a'));
    await nextJson(a);
    const b = await app.injectWS(`/signaling?token=${encodeURIComponent(tokenB)}`);
    b.send(offer('device-b'));
    await nextJson(b);
    expect(t.signalingService.hasActiveSession('resident-a')).toBe(true);
    expect(t.signalingService.hasActiveSession('resident-b')).toBe(true);
    a.close();
    b.close();
  });
});
