// HIGH-24 / MED-36 / LOW-25 / LOW-31 regression tests. Framework-level client
// errors must surface as 4xx (never a masked 500); the browser-facing security
// headers must be set; readiness must report; request ids must be UUIDs.

import { describe, it, expect, afterEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildTestApp, sessionFor } from '../helpers/test-app.js';
import { loadConfig } from '../../src/config.js';
import { buildContainer } from '../../src/container.js';
import { buildApp } from '../../src/app.js';
import type { TokenStorePort } from '../../src/services/stores.js';

let app: FastifyInstance | undefined;
afterEach(async () => {
  if (app) await app.close();
  app = undefined;
});

const SUB = 'resident-errhdr';
function auth(secret: string) {
  return { authorization: `Bearer ${sessionFor(SUB, secret)}` };
}

describe('HIGH-24 framework error handling', () => {
  it('maps a malformed JSON body to 400, not 500', async () => {
    const t = await buildTestApp();
    app = t.app;
    const res = await app.inject({
      method: 'POST',
      url: '/replies',
      headers: { ...auth(t.config.sessionSecret), 'content-type': 'application/json' },
      payload: '{ this is not json',
    });
    expect(res.statusCode).toBeGreaterThanOrEqual(400);
    expect(res.statusCode).toBeLessThan(500);
    expect(res.json().error.code).toBe('schema');
  });

  it('maps an oversized body to a 4xx, not 500', async () => {
    const t = await buildTestApp();
    app = t.app;
    // Exceed the configured bodyLimit so Fastify raises FST_ERR_CTP_BODY_TOO_LARGE.
    const huge = JSON.stringify({ visitorText: 'x'.repeat(2 * 1024 * 1024), mode: 'clarity' });
    const res = await app.inject({
      method: 'POST',
      url: '/replies',
      headers: { ...auth(t.config.sessionSecret), 'content-type': 'application/json' },
      payload: huge,
    });
    expect(res.statusCode).toBeGreaterThanOrEqual(400);
    expect(res.statusCode).toBeLessThan(500);
  });
});

describe('LOW-31 security headers', () => {
  it('sets nosniff and X-Frame-Options on responses', async () => {
    const t = await buildTestApp();
    app = t.app;
    const res = await app.inject({ method: 'GET', url: '/health' });
    expect(res.statusCode).toBe(200);
    expect(res.headers['x-content-type-options']).toBe('nosniff');
    expect(res.headers['x-frame-options']).toBe('DENY');
  });
});

describe('LOW-25 request ids', () => {
  it('generates a UUID request id surfaced in error envelopes', async () => {
    const t = await buildTestApp();
    app = t.app;
    const res = await app.inject({ method: 'GET', url: '/does-not-exist' });
    expect(res.statusCode).toBe(404);
    const requestId = res.json().error.requestId as string;
    expect(requestId).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
    );
  });
});

describe('MED-36 readiness probe', () => {
  it('reports ready with its dependency checks', async () => {
    const t = await buildTestApp();
    app = t.app;
    const res = await app.inject({ method: 'GET', url: '/ready' });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.ready).toBe(true);
    expect(Array.isArray(body.checks)).toBe(true);
    expect(body.checks.some((c: { name: string }) => c.name === 'tokenStore')).toBe(true);
  });

  it('reports 503 with tokenStore ok:false when the token store probe rejects (M-4)', async () => {
    // Inject a token store whose get() rejects, standing in for an unreachable
    // real datastore. The bounded readiness probe must surface this as not-ready
    // rather than hanging or reporting ready.
    const config = loadConfig({ THRESHOLD_ENV: 'local', SESSION_SECRET: 'test-secret-for-sessions' });
    const failingTokenStore: TokenStorePort = {
      get: async () => {
        throw new Error('datastore unreachable');
      },
      put: async () => {},
      delete: async () => {},
    };
    const container = buildContainer(config, { tokenStore: failingTokenStore });
    const built = await buildApp(container);
    app = built;
    await app.ready();
    const res = await app.inject({ method: 'GET', url: '/ready' });
    expect(res.statusCode).toBe(503);
    const body = res.json();
    expect(body.ready).toBe(false);
    const tokenStoreCheck = body.checks.find((c: { name: string }) => c.name === 'tokenStore');
    expect(tokenStoreCheck.ok).toBe(false);
  });
});
