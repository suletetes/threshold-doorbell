import { describe, it, expect, afterEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildTestApp, sessionFor } from '../helpers/test-app.js';
import { computeTimestampedSignature } from '../../src/security/hmac.js';

let app: FastifyInstance | undefined;
afterEach(async () => {
  if (app) await app.close();
  app = undefined;
});

const SUB = 'resident-metrics';
function auth(secret: string) {
  return { authorization: `Bearer ${sessionFor(SUB, secret)}` };
}

describe('Metrics wiring (Task 28, design.md §10)', () => {
  it('increments schema_validation_failure on a schema error', async () => {
    const t = await buildTestApp();
    app = t.app;
    const res = await app.inject({
      method: 'POST',
      url: '/replies',
      headers: auth(t.config.sessionSecret),
      payload: { visitorText: { not: 'a string' }, mode: 'clarity' },
    });
    expect(res.statusCode).toBe(400);
    expect(t.metrics.counter('schema_validation_failure')).toBe(1);
  });

  it('increments bedrock_fallback when Bedrock errors', async () => {
    const t = await buildTestApp();
    app = t.app;
    t.bedrock.setError();
    const res = await app.inject({
      method: 'POST',
      url: '/replies',
      headers: auth(t.config.sessionSecret),
      payload: { visitorText: 'hello', mode: 'clarity' },
    });
    expect(res.statusCode).toBe(200);
    expect(t.metrics.counter('bedrock_fallback')).toBe(1);
  });

  it('does not increment bedrock_fallback on a successful suggestion', async () => {
    const t = await buildTestApp();
    app = t.app;
    const res = await app.inject({
      method: 'POST',
      url: '/replies',
      headers: auth(t.config.sessionSecret),
      payload: { visitorText: 'I have a package', mode: 'clarity' },
    });
    expect(res.statusCode).toBe(200);
    expect(t.metrics.counter('bedrock_fallback')).toBe(0);
  });

  it('increments refresh on a successful token refresh', async () => {
    const t = await buildTestApp();
    app = t.app;
    // Seed a valid, not-near-expiry Ring token for this resident so the refresh
    // path actually succeeds. The old test skipped the success branch entirely
    // (the resident had no token, so it always 401'd and asserted 0), so the
    // metric increment was never exercised.
    await t.container.ringTokens.persist(SUB, {
      accessToken: 'seeded-access-token',
      refreshToken: 'seeded-refresh-token',
      expiresAt: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
    });
    const res = await app.inject({
      method: 'POST',
      url: '/oauth/refresh',
      headers: auth(t.config.sessionSecret),
    });
    expect(res.statusCode).toBe(200);
    expect(t.metrics.counter('refresh')).toBe(1);
  });

  it('observes webhook_ack_ms on a valid signed webhook delivery (M-6)', async () => {
    const t = await buildTestApp();
    app = t.app;
    await t.deviceAccountStore.map('ring-doorbell-001', 'resident-account-1');
    const ts = new Date().toISOString();
    const raw = JSON.stringify({
      request_id: 'ack-metric-1',
      event_type: 'person_detected',
      device_id: 'ring-doorbell-001',
      timestamp: '2026-01-01T00:00:00.000Z',
    });
    const sig = computeTimestampedSignature(ts, raw, t.config.webhookHmacKey);
    const res = await app.inject({
      method: 'POST',
      url: '/webhook',
      headers: {
        'content-type': 'application/json',
        'x-ring-signature': sig,
        'x-ring-timestamp': ts,
      },
      payload: raw,
    });
    expect(res.statusCode).toBe(200);
    const summary = t.metrics.latency('webhook_ack_ms');
    expect(summary).not.toBeNull();
    expect(summary!.count).toBeGreaterThanOrEqual(1);
  });
});
