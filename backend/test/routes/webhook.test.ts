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
    expect(await t.eventStore.listOrdered()).toHaveLength(0);
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
