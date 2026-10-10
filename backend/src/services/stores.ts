// Datastore ports (design.md §3). Real adapters wrap DynamoDB; fixtures are
// in-memory. All resident-scoped reads/writes take residentSub as a parameter
// derived by the caller from the session (FR-8.7); the store never trusts a
// client-supplied identifier because it never receives one directly.

import type { Conversation, DoorEvent, RingTokenRecord } from '../domain/types.js';

// --- Ring token store (Task 4, FR-1.6) ---
export interface TokenStorePort {
  put(record: RingTokenRecord): Promise<void>;
  get(residentSub: string): Promise<RingTokenRecord | null>;
  delete(residentSub: string): Promise<void>;
}

// --- Event store (Task 5/6, FR-3.2 idempotency, FR-3.5 poll) ---
export interface PutEventResult {
  /** true when this requestId was new; false when a duplicate was found. */
  created: boolean;
  event: DoorEvent;
}

export interface EventStorePort {
  /**
   * Conditional put by requestId (idempotency key). If an event with the same
   * requestId already exists, returns { created: false, event: existing } and
   * does not overwrite. Otherwise stores and returns { created: true }. The
   * event carries its owning residentSub (server-derived, FR-8.7) so reads can
   * be scoped per resident.
   */
  putIfAbsent(event: DoorEvent): Promise<PutEventResult>;
  /**
   * Events for a single resident, ordered by timestamp ascending, optionally
   * filtered to events at/after `since`. residentSub is server-derived from the
   * session (FR-8.7); the store never returns another resident's events.
   */
  listOrdered(residentSub: string, since?: string): Promise<DoorEvent[]>;
}

// --- Conversation store (Task 9, FR-8) ---
export interface ConversationQuery {
  query?: string; // free-text search over turn text
  from?: string; // ISO date lower bound (inclusive), matched on startedAt
  to?: string; // ISO date upper bound (inclusive), matched on startedAt
}

export interface ConversationStorePort {
  create(conversation: Conversation): Promise<void>;
  get(residentSub: string, conversationId: string): Promise<Conversation | null>;
  /** All conversations for a resident, filtered and ordered by startedAt descending. */
  listOrdered(residentSub: string, filter: ConversationQuery): Promise<Conversation[]>;
  delete(residentSub: string, conversationId: string): Promise<boolean>;
  /** Erase every conversation for a resident. Returns count removed (FR-8.6). */
  deleteAllForResident(residentSub: string): Promise<number>;
}

// --- Device -> account mapping (Task 5/6, CRIT-04) ---
/**
 * Maps a Ring deviceId to the residentSub that owns it. Populated server-side
 * when OAuth completes or the device list is fetched; the webhook route uses it
 * to attribute an inbound event to the correct resident instead of a hard-coded
 * account (CRIT-04). A device that is not present is unmapped: its events are
 * quarantined rather than attributed to any real resident (FR-8.7).
 */
export interface DeviceAccountStorePort {
  /** Record that `deviceId` belongs to `residentSub`. Idempotent (last write wins). */
  map(deviceId: string, residentSub: string): Promise<void>;
  /** Record every device for a resident in one call (used after a device-list fetch). */
  mapAll(deviceIds: string[], residentSub: string): Promise<void>;
  /** The owning resident for a device, or null when the device is unmapped. */
  resolve(deviceId: string): Promise<string | null>;
  /** Remove every mapping for a resident (erasure, FR-8.6). Returns count removed. */
  deleteAllForResident(residentSub: string): Promise<number>;
}
