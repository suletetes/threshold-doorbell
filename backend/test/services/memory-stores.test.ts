import { describe, it, expect } from 'vitest';
import {
  MemoryConversationStore,
  MemoryEventStore,
  MemoryTokenStore,
} from '../../src/services/fixtures/memory-stores.js';
import type { Conversation, DoorEvent, RingTokenRecord } from '../../src/domain/types.js';

function makeEvent(overrides: Partial<DoorEvent> = {}): DoorEvent {
  return {
    eventId: 'e1',
    requestId: 'r1',
    residentSub: 'resident-a',
    type: 'person_detected',
    deviceId: 'd1',
    timestamp: '2026-01-01T00:00:00.000Z',
    confidence: 0.9,
    boundingBox: null,
    thumbnailUrl: null,
    processedAt: null,
    ...overrides,
  };
}

function makeConversation(overrides: Partial<Conversation> = {}): Conversation {
  return {
    conversationId: 'c1',
    deviceId: 'd1',
    residentSub: 'resident-a',
    startedAt: '2026-01-01T00:00:00.000Z',
    endedAt: null,
    mode: 'clarity',
    outboundAvailable: true,
    language: 'en-US',
    turns: [
      {
        turnId: 't1',
        speaker: 'visitor',
        text: 'hello there',
        confidence: 0.8,
        provisional: false,
        timestamp: '2026-01-01T00:00:01.000Z',
        source: 'transcribe',
      },
    ],
    expiresAt: '2026-04-01T00:00:00.000Z',
    ...overrides,
  };
}

describe('MemoryTokenStore', () => {
  it('put/get/delete round-trips and isolates copies', async () => {
    const store = new MemoryTokenStore();
    const rec: RingTokenRecord = {
      residentSub: 'resident-a',
      accessTokenEnc: 'enc-a',
      refreshTokenEnc: 'enc-r',
      expiresAt: '2026-01-01T00:00:00.000Z',
    };
    await store.put(rec);
    const got = await store.get('resident-a');
    expect(got).toEqual(rec);
    // Mutating the returned copy does not affect the store.
    got!.accessTokenEnc = 'mutated';
    expect((await store.get('resident-a'))!.accessTokenEnc).toBe('enc-a');
    await store.delete('resident-a');
    expect(await store.get('resident-a')).toBeNull();
  });
});

describe('MemoryEventStore', () => {
  it('enforces idempotency by requestId (FR-3.2)', async () => {
    const store = new MemoryEventStore();
    const first = await store.putIfAbsent(makeEvent());
    expect(first.created).toBe(true);
    const dupe = await store.putIfAbsent(makeEvent({ eventId: 'e2', type: 'motion_detected' }));
    expect(dupe.created).toBe(false);
    // The stored event is the original, not the duplicate.
    expect(dupe.event.eventId).toBe('e1');
  });

  it('lists ordered by timestamp and filters by since', async () => {
    const store = new MemoryEventStore();
    await store.putIfAbsent(makeEvent({ requestId: 'r2', eventId: 'e2', timestamp: '2026-01-02T00:00:00.000Z' }));
    await store.putIfAbsent(makeEvent({ requestId: 'r1', eventId: 'e1', timestamp: '2026-01-01T00:00:00.000Z' }));
    const all = await store.listOrdered('resident-a');
    expect(all.map((e) => e.eventId)).toEqual(['e1', 'e2']);
    const recent = await store.listOrdered('resident-a', '2026-01-02T00:00:00.000Z');
    expect(recent.map((e) => e.eventId)).toEqual(['e2']);
  });

  it('scopes listOrdered by residentSub: a foreign resident\'s events never leak (AT-19)', async () => {
    const store = new MemoryEventStore();
    await store.putIfAbsent(makeEvent({ requestId: 'ra', eventId: 'ea', residentSub: 'resident-a' }));
    await store.putIfAbsent(makeEvent({ requestId: 'rb', eventId: 'eb', residentSub: 'resident-b' }));
    const listA = await store.listOrdered('resident-a');
    expect(listA.map((e) => e.eventId)).toEqual(['ea']);
    const listB = await store.listOrdered('resident-b');
    expect(listB.map((e) => e.eventId)).toEqual(['eb']);
  });
});

describe('MemoryConversationStore', () => {
  it('scopes reads by residentSub (FR-8.7)', async () => {
    const store = new MemoryConversationStore();
    await store.create(makeConversation({ conversationId: 'c1', residentSub: 'resident-a' }));
    await store.create(makeConversation({ conversationId: 'c2', residentSub: 'resident-b' }));
    expect(await store.get('resident-a', 'c1')).not.toBeNull();
    // resident-a cannot read resident-b's conversation.
    expect(await store.get('resident-a', 'c2')).toBeNull();
    const listA = await store.listOrdered('resident-a', {});
    expect(listA.map((c) => c.conversationId)).toEqual(['c1']);
  });

  it('filters by free-text query and date range', async () => {
    const store = new MemoryConversationStore();
    await store.create(
      makeConversation({ conversationId: 'c1', startedAt: '2026-01-01T00:00:00.000Z' }),
    );
    await store.create(
      makeConversation({
        conversationId: 'c2',
        startedAt: '2026-02-01T00:00:00.000Z',
        turns: [
          {
            turnId: 't1',
            speaker: 'visitor',
            text: 'package delivery',
            confidence: 0.9,
            provisional: false,
            timestamp: '2026-02-01T00:00:01.000Z',
            source: 'transcribe',
          },
        ],
      }),
    );
    const byQuery = await store.listOrdered('resident-a', { query: 'package' });
    expect(byQuery.map((c) => c.conversationId)).toEqual(['c2']);
    const byDate = await store.listOrdered('resident-a', {
      from: '2026-01-15T00:00:00.000Z',
      to: '2026-03-01T00:00:00.000Z',
    });
    expect(byDate.map((c) => c.conversationId)).toEqual(['c2']);
  });

  it('orders by startedAt descending', async () => {
    const store = new MemoryConversationStore();
    await store.create(makeConversation({ conversationId: 'old', startedAt: '2026-01-01T00:00:00.000Z' }));
    await store.create(makeConversation({ conversationId: 'new', startedAt: '2026-03-01T00:00:00.000Z' }));
    const list = await store.listOrdered('resident-a', {});
    expect(list.map((c) => c.conversationId)).toEqual(['new', 'old']);
  });

  it('deletes one and erases all for a resident (FR-8.4, FR-8.6)', async () => {
    const store = new MemoryConversationStore();
    await store.create(makeConversation({ conversationId: 'c1' }));
    await store.create(makeConversation({ conversationId: 'c2' }));
    expect(await store.delete('resident-a', 'c1')).toBe(true);
    expect(await store.delete('resident-a', 'missing')).toBe(false);
    const removed = await store.deleteAllForResident('resident-a');
    expect(removed).toBe(1);
    expect(await store.listOrdered('resident-a', {})).toEqual([]);
  });
});
