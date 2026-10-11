import { describe, it, expect } from 'vitest';
import { RETENTION_DAYS, TranscriptService } from '../../src/services/transcript-service.js';
import {
  MemoryConversationStore,
  MemoryTokenStore,
} from '../../src/services/fixtures/memory-stores.js';
import type { Conversation } from '../../src/domain/types.js';

// A pinned "now" so the server-time TTL (MED-26) is deterministic. startedAt in
// validInput is before this instant so it is never a future-timestamp rejection.
const NOW_MS = Date.parse('2026-06-01T00:00:00.000Z');

function build() {
  const store = new MemoryConversationStore();
  const tokens = new MemoryTokenStore();
  return { store, tokens, svc: new TranscriptService(store, tokens, {}, () => NOW_MS) };
}

const validInput = {
  deviceId: 'ring-doorbell-001',
  mode: 'clarity',
  language: 'en-US',
  outboundAvailable: true,
  startedAt: '2026-01-01T00:00:00.000Z',
  turns: [
    { speaker: 'visitor', text: 'hello', source: 'transcribe', confidence: 0.9 },
    { speaker: 'resident', text: 'Please leave it at the door', source: 'template' },
  ],
};

describe('TranscriptService (Task 9, FR-8)', () => {
  it('forces residentSub to the session subject (FR-8.7)', () => {
    const { svc } = build();
    const c = svc.buildConversation({ ...validInput }, 'resident-a');
    expect(c.residentSub).toBe('resident-a');
  });

  it('tolerates a matching client residentSub', () => {
    const { svc } = build();
    const c = svc.buildConversation(
      { ...validInput, residentSub: 'resident-a' },
      'resident-a',
    );
    expect(c.residentSub).toBe('resident-a');
  });

  it('rejects a foreign residentSub with 403 (AT-19)', () => {
    const { svc } = build();
    expect(() =>
      svc.buildConversation({ ...validInput, residentSub: 'resident-b' }, 'resident-a'),
    ).toThrowError(/own data/);
  });

  it('stamps a 90-day TTL from the server receive time, not startedAt (MED-26, FR-8.5)', () => {
    const { svc } = build();
    const c = svc.buildConversation({ ...validInput }, 'resident-a');
    const expires = Date.parse(c.expiresAt);
    // The TTL is anchored to the pinned server "now", not the client startedAt.
    expect(Math.round((expires - NOW_MS) / (24 * 60 * 60 * 1000))).toBe(RETENTION_DAYS);
  });

  it('rejects a future startedAt so retention cannot be bypassed (MED-26)', () => {
    const { svc } = build();
    expect(() =>
      svc.buildConversation({ ...validInput, startedAt: '9999-01-01T00:00:00.000Z' }, 'resident-a'),
    ).toThrow();
  });

  it('rejects malformed input', () => {
    const { svc } = build();
    expect(() => svc.buildConversation({ mode: 'clarity', language: 'en' }, 'a')).toThrow();
    expect(() =>
      svc.buildConversation({ deviceId: 'd', mode: 'bad', language: 'en' }, 'a'),
    ).toThrow();
    expect(() =>
      svc.buildConversation({ deviceId: 'd', mode: 'clarity', language: '' }, 'a'),
    ).toThrow();
  });

  it('rejects a finalized caption turn with no confidence (FR-5.7 coherence)', () => {
    const { svc } = build();
    expect(() =>
      svc.buildConversation(
        {
          ...validInput,
          turns: [{ speaker: 'visitor', text: 'x', source: 'transcribe', provisional: false }],
        },
        'a',
      ),
    ).toThrow();
  });

  it('accepts a provisional unfinalized turn with null confidence (FR-5.7)', () => {
    const { svc } = build();
    const c = svc.buildConversation(
      {
        ...validInput,
        turns: [
          {
            speaker: 'visitor',
            text: 'partial...',
            source: 'transcribe',
            provisional: true,
            confidence: null,
          },
        ],
      },
      'a',
    );
    expect(c.turns[0]!.provisional).toBe(true);
    expect(c.turns[0]!.confidence).toBeNull();
  });

  it('erases all transcripts and revokes tokens (FR-8.6)', async () => {
    const { store, tokens, svc } = build();
    await svc.create({ ...validInput, conversationId: 'c1' }, 'resident-a');
    await tokens.put({
      residentSub: 'resident-a',
      accessTokenEnc: 'x',
      refreshTokenEnc: 'y',
      expiresAt: '2026-01-01T00:00:00.000Z',
    });
    await svc.eraseAll('resident-a');
    expect(await store.listOrdered('resident-a', {})).toEqual([]);
    expect(await tokens.get('resident-a')).toBeNull();
  });

  it('detects expired conversations (FR-8.5)', () => {
    const expired: Conversation = {
      conversationId: 'c1',
      deviceId: 'd1',
      residentSub: 'resident-a',
      startedAt: '2020-01-01T00:00:00.000Z',
      endedAt: null,
      mode: 'clarity',
      outboundAvailable: true,
      language: 'en-US',
      turns: [],
      expiresAt: '2020-04-01T00:00:00.000Z',
    };
    expect(TranscriptService.isExpired(expired)).toBe(true);
  });
});
