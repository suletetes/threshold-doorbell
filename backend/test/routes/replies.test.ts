import { describe, it, expect, afterEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildTestApp, sessionFor } from '../helpers/test-app.js';
import { FIXED_SAFE_REPLIES } from '../../src/domain/types.js';

let app: FastifyInstance | undefined;
afterEach(async () => {
  if (app) await app.close();
  app = undefined;
});

const SUB = 'resident-a';
function auth(secret: string) {
  return { authorization: `Bearer ${sessionFor(SUB, secret)}` };
}

describe('POST /replies (Task 10, AT-7)', () => {
  it('requires a session', async () => {
    const t = await buildTestApp();
    app = t.app;
    const res = await app.inject({ method: 'POST', url: '/replies' });
    expect(res.statusCode).toBe(401);
  });

  it('returns at most 3 suggestions in Clarity Mode', async () => {
    const t = await buildTestApp();
    app = t.app;
    const res = await app.inject({
      method: 'POST',
      url: '/replies',
      headers: auth(t.config.sessionSecret),
      payload: { visitorText: 'I have a package', language: 'en-US', mode: 'clarity' },
    });
    expect(res.statusCode).toBe(200);
    const s = res.json().suggestions;
    expect(Array.isArray(s)).toBe(true);
    expect(s.length).toBeLessThanOrEqual(3);
  });

  it('returns the fixed safe set when Bedrock is blocked (AT-7)', async () => {
    const t = await buildTestApp();
    app = t.app;
    t.bedrock.setError();
    const res = await app.inject({
      method: 'POST',
      url: '/replies',
      headers: auth(t.config.sessionSecret),
      payload: { visitorText: 'hi', language: 'en-US', mode: 'clarity' },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().suggestions).toEqual(FIXED_SAFE_REPLIES.map((x) => x));
  });

  it('never calls Bedrock in Privacy Mode and returns the fixed safe set (FR-7.1a)', async () => {
    const t = await buildTestApp();
    app = t.app;
    // Even if Bedrock would error, Privacy Mode must not touch it.
    t.bedrock.setError();
    const res = await app.inject({
      method: 'POST',
      url: '/replies',
      headers: auth(t.config.sessionSecret),
      payload: { visitorText: 'anything', language: 'en-US', mode: 'privacy' },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().suggestions).toEqual(FIXED_SAFE_REPLIES.map((x) => x));
  });

  it('reply bar is never empty even with no visitor text', async () => {
    const t = await buildTestApp();
    app = t.app;
    const res = await app.inject({
      method: 'POST',
      url: '/replies',
      headers: auth(t.config.sessionSecret),
      payload: { mode: 'clarity' },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().suggestions.length).toBeGreaterThan(0);
  });

  it('rejects a mode other than clarity or privacy with 400 (MED-24)', async () => {
    const t = await buildTestApp();
    app = t.app;
    for (const mode of ['Privacy', 'PRIVACY', 'private', 'Clarity', 'x']) {
      const res = await app.inject({
        method: 'POST',
        url: '/replies',
        headers: auth(t.config.sessionSecret),
        payload: { visitorText: 'hello', mode },
      });
      expect(res.statusCode, `mode=${mode}`).toBe(400);
      expect(res.json().error.code).toBe('schema');
    }
  });

  it('defaults a missing mode to privacy and never calls Bedrock (MED-24 fail-closed)', async () => {
    const t = await buildTestApp();
    app = t.app;
    t.bedrock.setError(); // would throw if Bedrock were called
    const res = await app.inject({
      method: 'POST',
      url: '/replies',
      headers: auth(t.config.sessionSecret),
      payload: { visitorText: 'anything' }, // no mode
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().suggestions).toEqual(FIXED_SAFE_REPLIES.map((x) => x));
  });

  it('rejects non-string visitorText (FR-7.4 text-only)', async () => {
    const t = await buildTestApp();
    app = t.app;
    const res = await app.inject({
      method: 'POST',
      url: '/replies',
      headers: auth(t.config.sessionSecret),
      payload: { visitorText: { blob: 'binary' }, mode: 'clarity' },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('schema');
  });
});
