// H-1 regression: the WebSocket routes must honour the post-erasure session
// deny-list (HIGH-23) the same way the HTTP guard does. Mirrors the HTTP test
// 'DELETE /me/data invalidates existing sessions (HIGH-23 deny-list)' in
// transcripts.test.ts, but for /signaling and /asr/stream.
//
// Before the fix, authenticateWs only ran verifySession and never consulted
// sessionInvalidation, so a still-valid pre-erasure bearer (inside its 30-min
// absolute window) could open a live Ring signaling session and an
// Amazon-Transcribe-billing ASR relay after DELETE /me/data. Both routes must
// now close such a bearer with the 4401 unauthorized close code.

import { describe, it, expect, afterEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildTestApp, sessionFor } from '../helpers/test-app.js';
import { collectUntilClose, nextJson } from '../helpers/ws.js';
import { SIGNALING_CLOSE } from '../../src/routes/signaling.js';
import { ASR_CLOSE } from '../../src/routes/asr.js';
import { WS_SESSION_PROTOCOL_PREFIX } from '../../src/security/ws-auth.js';

let app: FastifyInstance | undefined;
afterEach(async () => {
  if (app) await app.close();
  app = undefined;
});

const SUB = 'resident-erasure';
const DEVICE = 'ring-front-door';

function signalingConnect(instance: FastifyInstance, token: string) {
  return instance.injectWS('/signaling', {
    headers: { 'sec-websocket-protocol': `${WS_SESSION_PROTOCOL_PREFIX}${token}` },
  });
}

function asrConnect(instance: FastifyInstance, token: string) {
  return instance.injectWS('/asr/stream', {
    headers: { 'sec-websocket-protocol': `${WS_SESSION_PROTOCOL_PREFIX}${token}` },
  });
}

/**
 * Authorize a resident for a device: persist a Ring token and map the device to
 * the resident (HIGH-20 ownership), mirroring the signaling tests' authorize().
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
    sdp: ['v=0', 'm=audio 9 UDP/TLS/RTP/SAVPF 111', 'a=sendrecv', 'm=video 9 UDP/TLS/RTP/SAVPF 96', 'a=recvonly'].join('\r\n'),
  });
}

describe('WS routes honour the post-erasure deny-list (H-1, HIGH-23)', () => {
  it('closes a pre-erasure bearer with 4401 on /signaling', async () => {
    const t = await buildTestApp();
    app = t.app;
    await authorize(t, SUB);
    // A session issued BEFORE the erasure cutoff.
    const stale = sessionFor(SUB, t.config.sessionSecret);
    // Match the HTTP test: a tiny delay so the pre-erasure iat is <= cutoff.
    await new Promise((r) => setTimeout(r, 2));
    await t.container.sessionInvalidation.revokeSessionsIssuedBefore(SUB, Date.now());

    const ws = await signalingConnect(app, stale);
    const { frames, code } = await collectUntilClose(ws);
    expect(code).toBe(SIGNALING_CLOSE.unauthorized);
    expect(frames[0]).toMatchObject({ type: 'error', code: 'unauthorized' });
    // No session was opened for the revoked bearer.
    expect(t.signalingService.hasActiveSession(SUB)).toBe(false);
  });

  it('closes a pre-erasure bearer with 4401 on /asr/stream', async () => {
    const t = await buildTestApp();
    app = t.app;
    const stale = sessionFor(SUB, t.config.sessionSecret);
    await new Promise((r) => setTimeout(r, 2));
    await t.container.sessionInvalidation.revokeSessionsIssuedBefore(SUB, Date.now());

    const ws = await asrConnect(app, stale);
    const { frames, code } = await collectUntilClose(ws);
    expect(code).toBe(ASR_CLOSE.unauthorized);
    expect(frames[0]).toMatchObject({ type: 'error', code: 'unauthorized' });
  });

  it('refuses a pre-erasure bearer on BOTH routes after a real DELETE /me/data', async () => {
    const t = await buildTestApp();
    app = t.app;
    await authorize(t, SUB);
    const stale = sessionFor(SUB, t.config.sessionSecret);
    await new Promise((r) => setTimeout(r, 2));
    // Drive the real eraseAll path so revocation goes through DELETE /me/data.
    const del = await app.inject({
      method: 'DELETE',
      url: '/me/data',
      headers: { authorization: `Bearer ${stale}` },
    });
    expect(del.statusCode).toBe(204);
    await new Promise((r) => setTimeout(r, 2));

    const sig = await signalingConnect(app, stale);
    const sigResult = await collectUntilClose(sig);
    expect(sigResult.code).toBe(SIGNALING_CLOSE.unauthorized);

    const asr = await asrConnect(app, stale);
    const asrResult = await collectUntilClose(asr);
    expect(asrResult.code).toBe(ASR_CLOSE.unauthorized);
  });

  it('a session issued AFTER the erasure cutoff still authenticates on /signaling (no over-revocation)', async () => {
    const t = await buildTestApp();
    app = t.app;
    await authorize(t, SUB);
    // Revoke everything up to now, then issue a fresh session afterwards.
    await t.container.sessionInvalidation.revokeSessionsIssuedBefore(SUB, Date.now());
    await new Promise((r) => setTimeout(r, 2));
    const fresh = sessionFor(SUB, t.config.sessionSecret);

    const ws = await signalingConnect(app, fresh);
    ws.send(offer());
    const answer = await nextJson(ws);
    expect(answer).toMatchObject({ type: 'answer' });
    expect(t.signalingService.hasActiveSession(SUB)).toBe(true);
    ws.close();
  });
});
