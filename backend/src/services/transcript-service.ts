// Transcript service (Task 9, FR-8.1..8.7). Validates and normalizes a create
// request, ALWAYS sets residentSub from the session (never the client, FR-8.7),
// stamps a 90-day TTL (FR-8.5), and provides list/get/delete plus full erasure
// (FR-8.6). A client-supplied residentSub that conflicts is rejected 403.

import { randomUUID } from 'node:crypto';
import { errors } from '../domain/errors.js';
import type {
  CaptionMode,
  Conversation,
  Speaker,
  Turn,
  TurnSource,
} from '../domain/types.js';
import type {
  ConversationQuery,
  ConversationStorePort,
  DeviceAccountStorePort,
  EventStorePort,
} from './stores.js';
import type { TokenStorePort } from './stores.js';
import type { SessionInvalidationPort } from './session-invalidation.js';

/**
 * The additional collaborators erasure needs beyond the conversation store:
 * events, the device mapping, token revocation, and session invalidation
 * (HIGH-23). Each is optional so narrow unit tests can still build the service
 * with only a conversation store and token store.
 */
export interface ErasureDeps {
  events?: EventStorePort;
  deviceAccounts?: DeviceAccountStorePort;
  sessionInvalidation?: SessionInvalidationPort;
}

export const RETENTION_DAYS = 90;
const RETENTION_MS = RETENTION_DAYS * 24 * 60 * 60 * 1000;

// M-2: bound the per-request transcript size well below the 64 KiB global body
// limit. A conversation is a handful of short turns; these caps reject a
// pathological payload (thousands of turns, or a single multi-kilobyte turn)
// with the uniform 400 'schema' envelope instead of parsing and storing it.
const MAX_TURNS_PER_TRANSCRIPT = 500;
const MAX_TURN_TEXT_CHARS = 2048;
// Allowance for client/server clock skew when rejecting a future startedAt (MED-26).
const CLOCK_SKEW_MS = 5 * 60 * 1000;

const SPEAKERS: readonly Speaker[] = ['visitor', 'resident'];
const SOURCES: readonly TurnSource[] = ['transcribe', 'ondevice', 'template', 'freetext'];
const MODES: readonly CaptionMode[] = ['clarity', 'privacy'];

/** Raw list filter from the query string (MED-27: parsed/validated here). */
export interface TranscriptListFilter {
  query?: string;
  from?: string;
  to?: string;
}

const DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;
const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Parse a date-filter bound to epoch ms (MED-27). A full ISO timestamp is used
 * as-is. A date-only value (YYYY-MM-DD) is anchored to the start of that UTC day
 * for a lower bound and widened to the END of that day for an upper bound, so a
 * same-day transcript is inclusive. Returns null for an unparseable value.
 */
function parseDateBound(value: string, edge: 'start' | 'end'): number | null {
  if (DATE_ONLY.test(value)) {
    const startOfDay = Date.parse(`${value}T00:00:00.000Z`);
    if (!Number.isFinite(startOfDay)) return null;
    return edge === 'end' ? startOfDay + DAY_MS - 1 : startOfDay;
  }
  const ms = Date.parse(value);
  return Number.isFinite(ms) ? ms : null;
}

// The shape a client may submit to POST /transcripts. residentSub is NOT part of
// the accepted input; if present and conflicting, the request is rejected 403.
export interface TranscriptCreateInput {
  conversationId?: unknown;
  deviceId?: unknown;
  residentSub?: unknown; // tolerated only if it equals the session sub (FR-8.7)
  startedAt?: unknown;
  endedAt?: unknown;
  mode?: unknown;
  outboundAvailable?: unknown;
  language?: unknown;
  turns?: unknown;
}

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

function parseTurn(raw: unknown): Turn {
  if (!isObject(raw)) throw errors.schema('Malformed turn.');
  if (typeof raw.speaker !== 'string' || !SPEAKERS.includes(raw.speaker as Speaker)) {
    throw errors.schema('Invalid turn speaker.');
  }
  if (typeof raw.text !== 'string') throw errors.schema('Turn text must be a string.');
  // M-2: cap a single turn's text so one oversized turn cannot bloat storage.
  if (raw.text.length > MAX_TURN_TEXT_CHARS) throw errors.schema('Turn text is too long.');
  if (typeof raw.source !== 'string' || !SOURCES.includes(raw.source as TurnSource)) {
    throw errors.schema('Invalid turn source.');
  }
  // confidence is nullable (FR-5.7); when present it must be a number in [0,1].
  let confidence: number | null = null;
  if (raw.confidence !== null && raw.confidence !== undefined) {
    if (typeof raw.confidence !== 'number' || raw.confidence < 0 || raw.confidence > 1) {
      throw errors.schema('Turn confidence out of range.');
    }
    confidence = raw.confidence;
  }
  const provisional = raw.provisional === true;
  // A finalized turn (not provisional) must carry a confidence; an unfinalized
  // one must be null (FR-5.7 coherence).
  if (!provisional && confidence === null) {
    // Allow template/freetext resident turns to be final with no ASR confidence.
    if (raw.source === 'transcribe' || raw.source === 'ondevice') {
      throw errors.schema('Finalized caption turn requires a confidence.');
    }
  }
  return {
    turnId: typeof raw.turnId === 'string' && raw.turnId !== '' ? raw.turnId : randomUUID(),
    speaker: raw.speaker as Speaker,
    text: raw.text,
    confidence,
    provisional,
    timestamp:
      typeof raw.timestamp === 'string' && raw.timestamp !== ''
        ? raw.timestamp
        : new Date().toISOString(),
    source: raw.source as TurnSource,
  };
}

export class TranscriptService {
  constructor(
    private readonly store: ConversationStorePort,
    private readonly tokens: TokenStorePort,
    private readonly erasure: ErasureDeps = {},
    // MED-26: injectable clock so the server receive time (not the client
    // startedAt) anchors the retention TTL, and so tests can pin "now".
    private readonly now: () => number = () => Date.now(),
  ) {}

  /**
   * Build a Conversation from client input with residentSub forced to the
   * session subject. Rejects 403 if the client supplied a different residentSub
   * (FR-8.7). Stamps the 90-day TTL from startedAt (FR-8.5).
   */
  buildConversation(input: TranscriptCreateInput, residentSub: string): Conversation {
    if (!isObject(input)) throw errors.schema('Malformed transcript.');

    // FR-8.7: a foreign residentSub is rejected; a matching one is tolerated.
    if (
      input.residentSub !== undefined &&
      input.residentSub !== null &&
      input.residentSub !== residentSub
    ) {
      throw errors.residentMismatch();
    }

    if (typeof input.deviceId !== 'string' || input.deviceId === '') {
      throw errors.schema('Missing deviceId.');
    }
    if (typeof input.mode !== 'string' || !MODES.includes(input.mode as CaptionMode)) {
      throw errors.schema('Invalid mode.');
    }
    // MED-25: Privacy Mode keeps audio AND transcript text on the handset; the
    // privacy policy promises "neither the audio nor the transcript text leaves
    // the handset" (PRIVACY_POLICY.md, FR-5.2/NFR-4). A privacy-mode transcript
    // must therefore never be uploaded for server-side storage. Reject it so
    // the code and the policy agree.
    if ((input.mode as CaptionMode) === 'privacy') {
      throw errors.schema('Privacy Mode transcripts stay on the device and cannot be uploaded.');
    }
    if (typeof input.language !== 'string' || input.language === '') {
      throw errors.schema('Missing language.');
    }
    const receivedMs = this.now();
    const startedAt =
      typeof input.startedAt === 'string' && input.startedAt !== ''
        ? input.startedAt
        : new Date(receivedMs).toISOString();
    const startedMs = Date.parse(startedAt);
    if (!Number.isFinite(startedMs)) throw errors.schema('Invalid startedAt.');
    // MED-26: reject a future startedAt (with a small clock-skew allowance) so a
    // client cannot push the retention window out. The 90-day TTL is computed
    // from the SERVER receive time, not from the client-supplied startedAt, so
    // the retention floor (FR-8.5) cannot be bypassed with startedAt=9999-01-01.
    if (startedMs > receivedMs + CLOCK_SKEW_MS) {
      throw errors.schema('startedAt cannot be in the future.');
    }

    const endedAt =
      typeof input.endedAt === 'string' && input.endedAt !== '' ? input.endedAt : null;

    const turnsRaw = input.turns;
    if (turnsRaw !== undefined && !Array.isArray(turnsRaw)) {
      throw errors.schema('turns must be an array.');
    }
    // M-2: cap the number of turns before mapping so a huge array cannot be
    // parsed and stored. The global body limit is a coarse backstop; this is the
    // precise per-field bound.
    if (Array.isArray(turnsRaw) && turnsRaw.length > MAX_TURNS_PER_TRANSCRIPT) {
      throw errors.schema('Too many turns in one transcript.');
    }
    const turns: Turn[] = Array.isArray(turnsRaw) ? turnsRaw.map(parseTurn) : [];

    return {
      conversationId:
        typeof input.conversationId === 'string' && input.conversationId !== ''
          ? input.conversationId
          : randomUUID(),
      deviceId: input.deviceId,
      residentSub, // ALWAYS server-derived (FR-8.7)
      startedAt,
      endedAt,
      mode: input.mode as CaptionMode,
      outboundAvailable: input.outboundAvailable === true,
      language: input.language,
      turns,
      // MED-26: TTL anchored to the server receive time (FR-8.5), never to the
      // client-controlled startedAt.
      expiresAt: new Date(receivedMs + RETENTION_MS).toISOString(),
    };
  }

  async create(input: TranscriptCreateInput, residentSub: string): Promise<string> {
    const conversation = this.buildConversation(input, residentSub);
    // MED-28: a POST must not silently overwrite existing data. When the client
    // supplied a conversationId that already exists for this resident, reject
    // with 409 instead of replacing the stored turns. A server-generated id (the
    // default when none is supplied) never collides, so a well-behaved client is
    // unaffected.
    const clientSuppliedId =
      typeof input.conversationId === 'string' && input.conversationId !== '';
    if (clientSuppliedId) {
      const existing = await this.store.get(residentSub, conversation.conversationId);
      if (existing !== null) {
        throw errors.conflict('A transcript with that id already exists.');
      }
    }
    await this.store.create(conversation);
    return conversation.conversationId;
  }

  /**
   * List transcripts for a resident. MED-27: `from`/`to` are parsed to epoch
   * bounds here (not compared as ISO strings in the store); an unparseable
   * value is a 400, and a date-only `to` is widened to the end of that day so a
   * same-day transcript is inclusive.
   */
  async list(residentSub: string, filter: TranscriptListFilter): Promise<Conversation[]> {
    const query: ConversationQuery = { query: filter.query };
    if (filter.from !== undefined && filter.from !== '') {
      const fromMs = parseDateBound(filter.from, 'start');
      if (fromMs === null) throw errors.schema('Invalid "from" date.');
      query.fromMs = fromMs;
    }
    if (filter.to !== undefined && filter.to !== '') {
      const toMs = parseDateBound(filter.to, 'end');
      if (toMs === null) throw errors.schema('Invalid "to" date.');
      query.toMs = toMs;
    }
    return this.store.listOrdered(residentSub, query);
  }

  async get(residentSub: string, conversationId: string): Promise<Conversation | null> {
    return this.store.get(residentSub, conversationId);
  }

  async delete(residentSub: string, conversationId: string): Promise<boolean> {
    return this.store.delete(residentSub, conversationId);
  }

  /**
   * Erase ALL data for a resident and cut off their access (FR-8.6, HIGH-23):
   * delete conversations AND events, remove the device->account mapping, revoke
   * the stored Ring grant, and invalidate every existing session so the
   * stateless bearer cannot keep reading for up to 30 minutes.
   *
   * Each step is idempotent (deleting what is already gone is a no-op), so the
   * whole operation is safe to retry if any single step fails. The real
   * deployment performs the datastore deletions in a single transaction; here
   * the ordering (invalidate the session FIRST) ensures a concurrent request
   * cannot observe a half-erased state as still authorized.
   */
  async eraseAll(residentSub: string, now = Date.now()): Promise<void> {
    // Invalidate sessions first so an in-flight request stops being authorized
    // even if a later deletion step is retried.
    await this.erasure.sessionInvalidation?.revokeSessionsIssuedBefore(residentSub, now);
    await this.store.deleteAllForResident(residentSub);
    await this.erasure.events?.deleteAllForResident(residentSub);
    await this.erasure.deviceAccounts?.deleteAllForResident(residentSub);
    await this.tokens.delete(residentSub);
  }

  /**
   * Whether a conversation is past its retention window (FR-8.5). The store
   * enforces this with a TTL; this predicate makes the rule testable and lets a
   * read path filter defensively.
   */
  static isExpired(conversation: Conversation, now = Date.now()): boolean {
    const exp = Date.parse(conversation.expiresAt);
    return Number.isFinite(exp) && now >= exp;
  }
}
