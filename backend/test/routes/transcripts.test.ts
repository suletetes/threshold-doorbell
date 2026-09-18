import { describe, it, expect, afterEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildTestApp, sessionFor } from '../helpers/test-app.js';

let app: FastifyInstance | undefined;
afterEach(async () => {
  if (app) await app.close();
  app = undefined;
});

const SUB = 'resident-a';

function auth(secret: string, sub = SUB) {
  return { authorization: `Bearer ${sessionFor(sub, secret)}` };
}

// Use dates relative to "now" so the 90-day TTL never expires them mid-test.
const DAY = 24 * 60 * 60 * 1000;
function daysAgo(n: number): string {
  return new Date(Date.now() - n * DAY).toISOString();
}

const body = {
  deviceId: 'ring-doorbell-001',
  mode: 'clarity',
  language: 'en-US',
  outboundAvailable: true,
  startedAt: daysAgo(1),
  turns: [{ speaker: 'visitor', text: 'package delivery', source: 'transcribe', confidence: 0.9 }],
};

describe('Transcript routes (Task 9, AT-15, AT-19)', () => {
  it('all routes require a session', async () => {
    const t = await buildTestApp();
    app = t.app;
    expect((await app.inject({ method: 'GET', url: '/transcripts' })).statusCode).toBe(401);
    expect((await app.inject({ method: 'POST', url: '/transcripts' })).statusCode).toBe(401);
    expect((await app.inject({ method: 'DELETE', url: '/transcripts/x' })).statusCode).toBe(401);
    expect((await app.inject({ method: 'DELETE', url: '/me/data' })).statusCode).toBe(401);
  });

  it('creates a transcript with server-derived residentSub (201)', async () => {
    const t = await buildTestApp();
    app = t.app;
    const res = await app.inject({
      method: 'POST',
      url: '/transcripts',
      headers: auth(t.config.sessionSecret),
      payload: body,
    });
    expect(res.statusCode).toBe(201);
    const { conversationId } = res.json();
    expect(conversationId).toBeTruthy();
    const stored = await t.conversationStore.get(SUB, conversationId);
    expect(stored!.residentSub).toBe(SUB);
  });

  it('rejects a foreign residentSub with 403 (FR-8.7, AT-19)', async () => {
    const t = await buildTestApp();
    app = t.app;
    const res = await app.inject({
      method: 'POST',
      url: '/transcripts',
      headers: auth(t.config.sessionSecret),
      payload: { ...body, residentSub: 'someone-else' },
    });
    expect(res.statusCode).toBe(403);
    expect(res.json().error.code).toBe('resident_mismatch');
  });

  it('rejects a schema-invalid body with 400', async () => {
    const t = await buildTestApp();
    app = t.app;
    const res = await app.inject({
      method: 'POST',
      url: '/transcripts',
      headers: auth(t.config.sessionSecret),
      payload: { mode: 'clarity' },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('schema');
  });

  it('lists paginated, searchable, date-filtered transcripts scoped to the resident', async () => {
    const t = await buildTestApp();
    app = t.app;
    const headers = auth(t.config.sessionSecret);
    await app.inject({ method: 'POST', url: '/transcripts', headers, payload: { ...body, conversationId: 'c1', startedAt: daysAgo(30) } });
    await app.inject({
      method: 'POST',
      url: '/transcripts',
      headers,
      payload: {
        ...body,
        conversationId: 'c2',
        startedAt: daysAgo(2),
        turns: [{ speaker: 'visitor', text: 'hello neighbour', source: 'transcribe', confidence: 0.8 }],
      },
    });
    // Another resident's transcript must not appear.
    const otherHeaders = auth(t.config.sessionSecret, 'resident-b');
    await app.inject({ method: 'POST', url: '/transcripts', headers: otherHeaders, payload: { ...body, conversationId: 'cX' } });

    const all = await app.inject({ method: 'GET', url: '/transcripts', headers });
    expect(all.json().items).toHaveLength(2);
    // Descending by startedAt.
    expect(all.json().items[0].conversationId).toBe('c2');

    const byQuery = await app.inject({ method: 'GET', url: '/transcripts?query=package', headers });
    expect(byQuery.json().items.map((c: { conversationId: string }) => c.conversationId)).toEqual(['c1']);

    const byDate = await app.inject({
      method: 'GET',
      url: `/transcripts?from=${encodeURIComponent(daysAgo(15))}`,
      headers,
    });
    expect(byDate.json().items.map((c: { conversationId: string }) => c.conversationId)).toEqual(['c2']);
  });

  it('paginates with a stable cursor (AT-19)', async () => {
    const t = await buildTestApp();
    app = t.app;
    const headers = auth(t.config.sessionSecret);
    for (let i = 0; i < 4; i += 1) {
      await app.inject({
        method: 'POST',
        url: '/transcripts',
        headers,
        payload: { ...body, conversationId: `c${i}`, startedAt: daysAgo(i + 1) },
      });
    }
    const p1 = await app.inject({ method: 'GET', url: '/transcripts?limit=2', headers });
    expect(p1.json().items).toHaveLength(2);
    expect(p1.json().nextCursor).not.toBeNull();
    const p2 = await app.inject({
      method: 'GET',
      url: `/transcripts?limit=2&cursor=${encodeURIComponent(p1.json().nextCursor)}`,
      headers,
    });
    expect(p2.json().items).toHaveLength(2);
    expect(p2.json().nextCursor).toBeNull();
  });

  it('deletes a transcript (204) and 404s a missing one (FR-8.4)', async () => {
    const t = await buildTestApp();
    app = t.app;
    const headers = auth(t.config.sessionSecret);
    await app.inject({ method: 'POST', url: '/transcripts', headers, payload: { ...body, conversationId: 'c1' } });
    const del = await app.inject({ method: 'DELETE', url: '/transcripts/c1', headers });
    expect(del.statusCode).toBe(204);
    const again = await app.inject({ method: 'DELETE', url: '/transcripts/c1', headers });
    expect(again.statusCode).toBe(404);
  });

  it('DELETE /me/data erases transcripts and revokes tokens (AT-15, FR-8.6)', async () => {
    const t = await buildTestApp();
    app = t.app;
    const headers = auth(t.config.sessionSecret);
    await app.inject({ method: 'POST', url: '/transcripts', headers, payload: { ...body, conversationId: 'c1' } });
    await t.container.ringTokens.persist(SUB, {
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: new Date(Date.now() + 3600_000).toISOString(),
    });
    const res = await app.inject({ method: 'DELETE', url: '/me/data', headers });
    expect(res.statusCode).toBe(204);
    expect(await t.conversationStore.listOrdered(SUB, {})).toEqual([]);
    expect(await t.tokenStore.get(SUB)).toBeNull();
  });

  it('never surfaces an expired transcript (FR-8.5 defensive filter)', async () => {
    const t = await buildTestApp();
    app = t.app;
    // Directly seed an expired conversation.
    await t.conversationStore.create({
      conversationId: 'old',
      deviceId: 'd1',
      residentSub: SUB,
      startedAt: '2020-01-01T00:00:00.000Z',
      endedAt: null,
      mode: 'clarity',
      outboundAvailable: true,
      language: 'en-US',
      turns: [],
      expiresAt: '2020-04-01T00:00:00.000Z',
    });
    const res = await app.inject({ method: 'GET', url: '/transcripts', headers: auth(t.config.sessionSecret) });
    expect(res.json().items).toEqual([]);
  });
});
