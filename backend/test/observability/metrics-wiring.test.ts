import { describe, it, expect, afterEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildTestApp, sessionFor } from '../helpers/test-app.js';

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
});
