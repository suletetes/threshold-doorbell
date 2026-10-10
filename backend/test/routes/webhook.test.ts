import { describe, it, expect, afterEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildTestApp } from '../helpers/test-app.js';
import { computeSignature } from '../../src/security/hmac.js';

let app: FastifyInstance | undefined;
afterEach(async () => {
  if (app) await app.close();
  app = undefined;
});

function signed(body: object, key: string) {
  const raw = JSON.stringify(body);
  return { raw, sig: computeSignature(raw, key) };
}

/** Let queued microtasks (the async push) flush. */
async function flushMicrotasks(): Promise<void> {
  await new Promise((r) => setImmediate(r));
}

describe('POST /webhook (Task 5, AT-2)', () => {
  const payload = {
    request_id: 'req-1',
    event_type: 'person_detected',
    device_id: 'ring-doorbell-001',
    timestamp: '2026-01-01T00:00:00.000Z',
    thumbnail_url: 'https://example/thumb.jpg',
  };

  it('accepts a valid signed webhook, returns 200, and enqueues one push', async () => {
    const t = await buildTestApp();
    app = t.app;
    await t.deviceAccountStore.map('ring-doorbell-001', 'resident-account-1');
    const { raw, sig } = signed(payload, t.config.webhookHmacKey);
    const res = await app.inject({
      method: 'POST',
      url: '/webhook',
      headers: { 'content-type': 'application/json', 'x-ring-signature': sig },
      payload: raw,
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ok: true });
    await flushMicrotasks();
    expect(t.push.sent).toHaveLength(1);
    expect(t.push.sent[0]!.type).toBe('person_detected');
    expect(t.push.sent[0]!.deviceId).toBe('ring-doorbell-001');
  });

  it('deduplicates by requestId: two deliveries, one alert, both 200 (AT-2)', async () => {
    const t = await buildTestApp();
    app = t.app;
    await t.deviceAccountStore.map('ring-doorbell-001', 'resident-account-1');
    const { raw, sig } = signed(payload, t.config.webhookHmacKey);
    const headers = { 'content-type': 'application/json', 'x-ring-signature': sig };

    const first = await app.inject({ method: 'POST', url: '/webhook', headers, payload: raw });
    const second = await app.inject({ method: 'POST', url: '/webhook', headers, payload: raw });
    expect(first.statusCode).toBe(200);
    expect(second.statusCode).toBe(200);
    await flushMicrotasks();
    // Processed at most once: exactly one push despite two deliveries.
    expect(t.push.sent).toHaveLength(1);
  });

  it('rejects a bad signature with 401 and does not process (FR-3.1)', async () => {
    const t = await buildTestApp();
    app = t.app;
    const raw = JSON.stringify(payload);
    const res = await app.inject({
      method: 'POST',
      url: '/webhook',
      headers: { 'content-type': 'application/json', 'x-ring-signature': 'sha256=deadbeef' },
      payload: raw,
    });
    expect(res.statusCode).toBe(401);
    expect(res.json().error.code).toBe('bad_signature');
    await flushMicrotasks();
    expect(t.push.sent).toHaveLength(0);
    // Nothing was stored.
    expect(await t.eventStore.listOrdered('resident-account-1')).toHaveLength(0);
  });

  it('rejects a valid signature over a malformed payload with schema 400', async () => {
    const t = await buildTestApp();
    app = t.app;
    const { raw, sig } = signed({ event_type: 'person_detected' }, t.config.webhookHmacKey);
    const res = await app.inject({
      method: 'POST',
      url: '/webhook',
      headers: { 'content-type': 'application/json', 'x-ring-signature': sig },
      payload: raw,
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('schema');
  });

  it('rejects an unknown event_type', async () => {
    const t = await buildTestApp();
    app = t.app;
    const { raw, sig } = signed(
      { ...payload, request_id: 'req-2', event_type: 'alien_landing' },
      t.config.webhookHmacKey,
    );
    const res = await app.inject({
      method: 'POST',
      url: '/webhook',
      headers: { 'content-type': 'application/json', 'x-ring-signature': sig },
      payload: raw,
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('schema');
  });

  it('does not fail the request when push delivery fails (FR-3.5 fallback)', async () => {
    const t = await buildTestApp();
    app = t.app;
    await t.deviceAccountStore.map('ring-doorbell-001', 'resident-account-1');
    t.push.failOnce();
    const { raw, sig } = signed(
      { ...payload, request_id: 'req-3' },
      t.config.webhookHmacKey,
    );
    const res = await app.inject({
      method: 'POST',
      url: '/webhook',
      headers: { 'content-type': 'application/json', 'x-ring-signature': sig },
      payload: raw,
    });
    // The ack is still 200 even though push failed; app falls back to poll.
    expect(res.statusCode).toBe(200);
    await flushMicrotasks();
    expect(t.push.sent).toHaveLength(0);
  });
});

describe('POST /webhook tenancy isolation (CRIT-04)', () => {
  it('routes each device event to its mapped resident only, never to a hard-coded account', async () => {
    const t = await buildTestApp();
    app = t.app;
    const residentA = 'resident-aaa';
    const residentB = 'resident-bbb';
    // Two residents each own a distinct device (populated as /devices would).
    await t.deviceAccountStore.map('device-a', residentA);
    await t.deviceAccountStore.map('device-b', residentB);

    async function deliver(requestId: string, deviceId: string) {
      const body = {
        request_id: requestId,
        event_type: 'motion_detected',
        device_id: deviceId,
        timestamp: '2026-01-01T00:00:00.000Z',
      };
      const raw = JSON.stringify(body);
      const sig = computeSignature(raw, t.config.webhookHmacKey);
      const res = await app!.inject({
        method: 'POST',
        url: '/webhook',
        headers: { 'content-type': 'application/json', 'x-ring-signature': sig },
        payload: raw,
      });
      expect(res.statusCode).toBe(200);
    }

    await deliver('wa', 'device-a');
    await deliver('wb', 'device-b');
    await flushMicrotasks();

    // Resident A sees only device-a's event; resident B's never leaks in.
    const eventsA = await t.eventStore.listOrdered(residentA);
    expect(eventsA.map((e) => e.deviceId)).toEqual(['device-a']);
    const eventsB = await t.eventStore.listOrdered(residentB);
    expect(eventsB.map((e) => e.deviceId)).toEqual(['device-b']);

    // Neither resident ever receives the hard-coded 'resident-account-1' bucket.
    expect(await t.eventStore.listOrdered('resident-account-1')).toHaveLength(0);
  });

  it('quarantines events for an unmapped device (no real resident attribution)', async () => {
    const t = await buildTestApp();
    app = t.app;
    const body = {
      request_id: 'orphan-1',
      event_type: 'motion_detected',
      device_id: 'unmapped-device',
      timestamp: '2026-01-01T00:00:00.000Z',
    };
    const raw = JSON.stringify(body);
    const sig = computeSignature(raw, t.config.webhookHmacKey);
    const res = await app.inject({
      method: 'POST',
      url: '/webhook',
      headers: { 'content-type': 'application/json', 'x-ring-signature': sig },
      payload: raw,
    });
    expect(res.statusCode).toBe(200);
    await flushMicrotasks();
    // The unmapped event is NOT attributed to any real resident, and no push.
    expect(await t.eventStore.listOrdered('resident-account-1')).toHaveLength(0);
    expect(await t.eventStore.listOrdered('unmapped-device')).toHaveLength(0);
    expect(t.push.sent).toHaveLength(0);
  });
});
