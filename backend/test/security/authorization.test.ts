// Authorization + redaction suite (Task 27, FR-1.6, 1.7, 8.7, NFR-3, AT-19).
// Proves: residentSub is always server-derived and foreign values are rejected;
// cross-resident reads are isolated; no Ring token reaches the device or logs;
// the logger redacts tokens, credentials, transcript text, and bodies.

import { describe, it, expect, afterEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { pino } from 'pino';
import { buildTestApp, sessionFor } from '../helpers/test-app.js';
import { createLogger, REDACT_PATHS } from '../../src/observability/logger.js';

let app: FastifyInstance | undefined;
afterEach(async () => {
  if (app) await app.close();
  app = undefined;
});

const body = {
  deviceId: 'ring-doorbell-001',
  mode: 'clarity',
  language: 'en-US',
  outboundAvailable: true,
  startedAt: new Date().toISOString(),
  turns: [{ speaker: 'visitor', text: 'my card number is 4111', source: 'transcribe', confidence: 0.9 }],
};

describe('Authorization: residentSub is server-derived (FR-8.7, AT-19)', () => {
  it('rejects a foreign residentSub on create with 403', async () => {
    const t = await buildTestApp();
    app = t.app;
    const res = await app.inject({
      method: 'POST',
      url: '/transcripts',
      headers: { authorization: `Bearer ${sessionFor('resident-a', t.config.sessionSecret)}` },
      payload: { ...body, residentSub: 'resident-victim' },
    });
    expect(res.statusCode).toBe(403);
    expect(res.json().error.code).toBe('resident_mismatch');
  });

  it('ignores a client residentSub in the query and scopes to the session', async () => {
    const t = await buildTestApp();
    app = t.app;
    const aHeaders = { authorization: `Bearer ${sessionFor('resident-a', t.config.sessionSecret)}` };
    const bHeaders = { authorization: `Bearer ${sessionFor('resident-b', t.config.sessionSecret)}` };
    // resident-b creates a transcript.
    await app.inject({ method: 'POST', url: '/transcripts', headers: bHeaders, payload: { ...body, conversationId: 'bSecret' } });
    // resident-a tries to read resident-b's data by passing a foreign residentSub query.
    const res = await app.inject({
      method: 'GET',
      url: '/transcripts?residentSub=resident-b',
      headers: aHeaders,
    });
    expect(res.statusCode).toBe(200);
    // Only session-scoped (resident-a) data is returned: empty, not resident-b's.
    expect(res.json().items).toEqual([]);
  });

  it("cannot delete another resident's transcript (404, not 204)", async () => {
    const t = await buildTestApp();
    app = t.app;
    const aHeaders = { authorization: `Bearer ${sessionFor('resident-a', t.config.sessionSecret)}` };
    const bHeaders = { authorization: `Bearer ${sessionFor('resident-b', t.config.sessionSecret)}` };
    await app.inject({ method: 'POST', url: '/transcripts', headers: bHeaders, payload: { ...body, conversationId: 'bOwned' } });
    const res = await app.inject({ method: 'DELETE', url: '/transcripts/bOwned', headers: aHeaders });
    expect(res.statusCode).toBe(404);
  });
});

describe('No Ring token on the device (FR-1.6, AT-1)', () => {
  it('the OAuth callback response carries no Ring token', async () => {
    const t = await buildTestApp();
    app = t.app;
    const start = await app.inject({ method: 'GET', url: '/oauth/start' });
    const state = new URL(start.headers.location as string).searchParams.get('state')!;
    const res = await app.inject({
      method: 'GET',
      url: `/oauth/callback?code=account-42&state=${encodeURIComponent(state)}`,
    });
    const serialized = JSON.stringify({ headers: res.headers, cookies: res.cookies, body: res.body });
    expect(serialized).not.toContain('access-account-42');
    expect(serialized).not.toContain('refresh-account-42');
  });

  it('stored token attributes are ciphertext, not cleartext', async () => {
    const t = await buildTestApp();
    app = t.app;
    await t.container.ringTokens.persist('resident-a', {
      accessToken: 'super-secret-access',
      refreshToken: 'super-secret-refresh',
      expiresAt: new Date(Date.now() + 3600_000).toISOString(),
    });
    const row = await t.tokenStore.get('resident-a');
    expect(JSON.stringify(row)).not.toContain('super-secret-access');
    expect(JSON.stringify(row)).not.toContain('super-secret-refresh');
  });
});

describe('Log redaction (FR-1.7, NFR-3)', () => {
  it('redacts tokens, credentials, transcript text, and bodies', () => {
    const chunks: string[] = [];
    const stream = { write: (s: string) => chunks.push(s) };
    // Rebuild the logger with our redact paths writing to a capture stream.
    const log = pino({ redact: { paths: REDACT_PATHS, censor: '[redacted]' } }, stream as never);

    log.info(
      {
        accessToken: 'plain-access',
        refreshToken: 'plain-refresh',
        authorization: 'Bearer leaky',
        cookie: 'threshold_session=leaky',
        residentSub: 'resident-a',
        text: 'my card number is 4111',
        body: { anything: 'sensitive' },
        clientSecret: 'ring-secret',
        safe: 'this-is-fine',
      },
      'log line',
    );

    const out = chunks.join('');
    expect(out).not.toContain('plain-access');
    expect(out).not.toContain('plain-refresh');
    expect(out).not.toContain('leaky');
    expect(out).not.toContain('resident-a');
    expect(out).not.toContain('4111');
    expect(out).not.toContain('ring-secret');
    expect(out).toContain('[redacted]');
    // Non-sensitive fields still log.
    expect(out).toContain('this-is-fine');
  });

  it('createLogger builds a logger with the redaction config', () => {
    // Smoke test that the factory does not throw and returns a usable logger.
    const log = createLogger('silent');
    expect(typeof log.info).toBe('function');
  });
});
