import { describe, it, expect, afterEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildTestApp, sessionFor } from '../helpers/test-app.js';
import type { DoorEvent } from '../../src/domain/types.js';

let app: FastifyInstance | undefined;
afterEach(async () => {
  if (app) await app.close();
  app = undefined;
});

const SUB = 'resident-account-1';

async function seedTokens(container: { ringTokens: { persist: (s: string, t: { accessToken: string; refreshToken: string; expiresAt: string }) => Promise<void> } }) {
  await container.ringTokens.persist(SUB, {
    accessToken: 'a',
    refreshToken: 'r',
    expiresAt: new Date(Date.now() + 3600_000).toISOString(),
  });
}

function makeEvent(i: number, residentSub: string = SUB): DoorEvent {
  return {
    eventId: `e${i}`,
    requestId: `r${i}`,
    residentSub,
    type: 'motion_detected',
    deviceId: 'd1',
    timestamp: new Date(Date.UTC(2026, 0, 1, 0, 0, i)).toISOString(),
    confidence: null,
    boundingBox: null,
    thumbnailUrl: null,
    processedAt: null,
  };
}

describe('GET /devices (Task 6, AT-23)', () => {
  it('requires a session', async () => {
    const t = await buildTestApp();
    app = t.app;
    const res = await app.inject({ method: 'GET', url: '/devices' });
    expect(res.statusCode).toBe(401);
  });

  it('returns paginated devices for a session', async () => {
    const t = await buildTestApp();
    app = t.app;
    await seedTokens(t.container);
    const token = sessionFor(SUB, t.config.sessionSecret);
    const res = await app.inject({
      method: 'GET',
      url: '/devices',
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.items).toHaveLength(2);
    expect(body.nextCursor).toBeNull();
  });

  it('paginates with limit + cursor', async () => {
    const t = await buildTestApp();
    app = t.app;
    await seedTokens(t.container);
    const token = sessionFor(SUB, t.config.sessionSecret);
    const p1 = await app.inject({
      method: 'GET',
      url: '/devices?limit=1',
      headers: { authorization: `Bearer ${token}` },
    });
    const b1 = p1.json();
    expect(b1.items).toHaveLength(1);
    expect(b1.nextCursor).not.toBeNull();
    const p2 = await app.inject({
      method: 'GET',
      url: `/devices?limit=1&cursor=${encodeURIComponent(b1.nextCursor)}`,
      headers: { authorization: `Bearer ${token}` },
    });
    const b2 = p2.json();
    expect(b2.items).toHaveLength(1);
    expect(b2.items[0].id).not.toBe(b1.items[0].id);
  });

  it('returns an empty page for an account with no devices (FR-2.2)', async () => {
    const t = await buildTestApp();
    app = t.app;
    t.ring.setEmptyDevices();
    await seedTokens(t.container);
    const token = sessionFor(SUB, t.config.sessionSecret);
    const res = await app.inject({
      method: 'GET',
      url: '/devices',
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().items).toEqual([]);
  });

  it('returns 502 ring_contract_invalid on malformed Ring payload (AT-23)', async () => {
    const t = await buildTestApp();
    app = t.app;
    t.ring.setMalformedDevices();
    await seedTokens(t.container);
    const token = sessionFor(SUB, t.config.sessionSecret);
    const res = await app.inject({
      method: 'GET',
      url: '/devices',
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(502);
    expect(res.json().error.code).toBe('ring_contract_invalid');
  });

  it('rejects a malformed cursor with 400 schema', async () => {
    const t = await buildTestApp();
    app = t.app;
    await seedTokens(t.container);
    const token = sessionFor(SUB, t.config.sessionSecret);
    const res = await app.inject({
      method: 'GET',
      url: '/devices?cursor=not-valid!!',
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('schema');
  });
});

describe('GET /events (Task 6, FR-3.5, AT-19)', () => {
  it('requires a session', async () => {
    const t = await buildTestApp();
    app = t.app;
    const res = await app.inject({ method: 'GET', url: '/events' });
    expect(res.statusCode).toBe(401);
  });

  it('returns paginated events with a stable cursor', async () => {
    const t = await buildTestApp();
    app = t.app;
    for (let i = 0; i < 5; i += 1) {
      await t.eventStore.putIfAbsent(makeEvent(i));
    }
    const token = sessionFor(SUB, t.config.sessionSecret);
    const p1 = await app.inject({
      method: 'GET',
      url: '/events?limit=2',
      headers: { authorization: `Bearer ${token}` },
    });
    const b1 = p1.json();
    expect(b1.items).toHaveLength(2);
    expect(b1.items[0].eventId).toBe('e0');
    const p2 = await app.inject({
      method: 'GET',
      url: `/events?limit=2&cursor=${encodeURIComponent(b1.nextCursor)}`,
      headers: { authorization: `Bearer ${token}` },
    });
    expect(p2.json().items[0].eventId).toBe('e2');
  });

  it('filters by since', async () => {
    const t = await buildTestApp();
    app = t.app;
    for (let i = 0; i < 5; i += 1) {
      await t.eventStore.putIfAbsent(makeEvent(i));
    }
    const token = sessionFor(SUB, t.config.sessionSecret);
    const since = new Date(Date.UTC(2026, 0, 1, 0, 0, 3)).toISOString();
    const res = await app.inject({
      method: 'GET',
      url: `/events?since=${encodeURIComponent(since)}`,
      headers: { authorization: `Bearer ${token}` },
    });
    const items = res.json().items;
    expect(items.map((e: DoorEvent) => e.eventId)).toEqual(['e3', 'e4']);
  });

  it('returns ONLY the requesting resident\'s events, never a foreign resident\'s (AT-19)', async () => {
    const t = await buildTestApp();
    app = t.app;
    const residentA = 'resident-account-1';
    const residentB = 'resident-account-2';
    // Seed events for two distinct residents into the shared event store.
    await t.eventStore.putIfAbsent({ ...makeEvent(0, residentA), eventId: 'a0', requestId: 'ra0' });
    await t.eventStore.putIfAbsent({ ...makeEvent(1, residentA), eventId: 'a1', requestId: 'ra1' });
    await t.eventStore.putIfAbsent({ ...makeEvent(2, residentB), eventId: 'b0', requestId: 'rb0' });
    await t.eventStore.putIfAbsent({ ...makeEvent(3, residentB), eventId: 'b1', requestId: 'rb1' });

    const tokenA = sessionFor(residentA, t.config.sessionSecret);
    const resA = await app.inject({
      method: 'GET',
      url: '/events',
      headers: { authorization: `Bearer ${tokenA}` },
    });
    const idsA = resA.json().items.map((e: DoorEvent) => e.eventId).sort();
    expect(idsA).toEqual(['a0', 'a1']);
    // Resident A must NOT see any of resident B's events (cross-resident leak).
    expect(idsA).not.toContain('b0');
    expect(idsA).not.toContain('b1');

    const tokenB = sessionFor(residentB, t.config.sessionSecret);
    const resB = await app.inject({
      method: 'GET',
      url: '/events',
      headers: { authorization: `Bearer ${tokenB}` },
    });
    const idsB = resB.json().items.map((e: DoorEvent) => e.eventId).sort();
    expect(idsB).toEqual(['b0', 'b1']);
    expect(idsB).not.toContain('a0');
    expect(idsB).not.toContain('a1');
  });
});
