// In-memory fixture stores (design.md §11 "local"). Deterministic, no AWS.
// Used in local/demo environments and in every test.

import type { Conversation, DoorEvent, RingTokenRecord } from '../../domain/types.js';
import type {
  ConversationQuery,
  ConversationStorePort,
  EventStorePort,
  PutEventResult,
  TokenStorePort,
} from '../stores.js';

export class MemoryTokenStore implements TokenStorePort {
  private readonly rows = new Map<string, RingTokenRecord>();

  async put(record: RingTokenRecord): Promise<void> {
    this.rows.set(record.residentSub, { ...record });
  }

  async get(residentSub: string): Promise<RingTokenRecord | null> {
    const row = this.rows.get(residentSub);
    return row ? { ...row } : null;
  }

  async delete(residentSub: string): Promise<void> {
    this.rows.delete(residentSub);
  }

  /** Test helper: number of stored token rows. */
  size(): number {
    return this.rows.size;
  }
}

export class MemoryEventStore implements EventStorePort {
  // Keyed by requestId to enforce conditional-put idempotency (FR-3.2). The
  // idempotency key is global (Ring requestIds are unique per delivery); reads
  // are scoped per resident via the residentSub carried on each event (FR-8.7).
  private readonly byRequestId = new Map<string, DoorEvent>();

  async putIfAbsent(event: DoorEvent): Promise<PutEventResult> {
    const existing = this.byRequestId.get(event.requestId);
    if (existing) {
      return { created: false, event: { ...existing } };
    }
    this.byRequestId.set(event.requestId, { ...event });
    return { created: true, event: { ...event } };
  }

  async deleteAllForResident(residentSub: string): Promise<number> {
    let removed = 0;
    for (const [requestId, event] of this.byRequestId) {
      if (event.residentSub === residentSub) {
        this.byRequestId.delete(requestId);
        removed += 1;
      }
    }
    return removed;
  }

  async listOrdered(residentSub: string, since?: string): Promise<DoorEvent[]> {
    // Scope to the requesting resident: another resident's events are never
    // returned even though the idempotency map is global (FR-8.7, AT-19).
    const mine = [...this.byRequestId.values()].filter(
      (e) => e.residentSub === residentSub,
    );
    const filtered =
      since === undefined ? mine : mine.filter((e) => e.timestamp >= since);
    // Ascending by timestamp, then eventId for a stable total order.
    return filtered
      .sort((a, b) =>
        a.timestamp === b.timestamp
          ? a.eventId.localeCompare(b.eventId)
          : a.timestamp.localeCompare(b.timestamp),
      )
      .map((e) => ({ ...e }));
  }
}

export class MemoryConversationStore implements ConversationStorePort {
  // Map<residentSub, Map<conversationId, Conversation>>.
  private readonly byResident = new Map<string, Map<string, Conversation>>();

  async create(conversation: Conversation): Promise<void> {
    let bucket = this.byResident.get(conversation.residentSub);
    if (!bucket) {
      bucket = new Map();
      this.byResident.set(conversation.residentSub, bucket);
    }
    bucket.set(conversation.conversationId, clone(conversation));
  }

  async get(residentSub: string, conversationId: string): Promise<Conversation | null> {
    const found = this.byResident.get(residentSub)?.get(conversationId);
    return found ? clone(found) : null;
  }

  async listOrdered(
    residentSub: string,
    filter: ConversationQuery,
  ): Promise<Conversation[]> {
    const bucket = this.byResident.get(residentSub);
    if (!bucket) return [];
    let rows = [...bucket.values()];

    // MED-27: compare instants, not ISO strings, so a transcript on the same
    // day as a date-only bound is included (the service widened `toMs` to the
    // end of that day). A startedAt that cannot be parsed is excluded.
    if (filter.fromMs !== undefined) {
      const from = filter.fromMs;
      rows = rows.filter((c) => {
        const t = Date.parse(c.startedAt);
        return Number.isFinite(t) && t >= from;
      });
    }
    if (filter.toMs !== undefined) {
      const to = filter.toMs;
      rows = rows.filter((c) => {
        const t = Date.parse(c.startedAt);
        return Number.isFinite(t) && t <= to;
      });
    }
    if (filter.query !== undefined && filter.query.trim() !== '') {
      const needle = filter.query.toLowerCase();
      rows = rows.filter((c) =>
        c.turns.some((t) => t.text.toLowerCase().includes(needle)),
      );
    }

    // Descending by startedAt, then conversationId for a stable total order.
    return rows
      .sort((a, b) =>
        a.startedAt === b.startedAt
          ? a.conversationId.localeCompare(b.conversationId)
          : b.startedAt.localeCompare(a.startedAt),
      )
      .map(clone);
  }

  async delete(residentSub: string, conversationId: string): Promise<boolean> {
    return this.byResident.get(residentSub)?.delete(conversationId) ?? false;
  }

  async deleteAllForResident(residentSub: string): Promise<number> {
    const bucket = this.byResident.get(residentSub);
    if (!bucket) return 0;
    const count = bucket.size;
    this.byResident.delete(residentSub);
    return count;
  }
}

function clone(c: Conversation): Conversation {
  return { ...c, turns: c.turns.map((t) => ({ ...t })) };
}
