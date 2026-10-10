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

const SPEAKERS: readonly Speaker[] = ['visitor', 'resident'];
const SOURCES: readonly TurnSource[] = ['transcribe', 'ondevice', 'template', 'freetext'];
const MODES: readonly CaptionMode[] = ['clarity', 'privacy'];

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
    const startedAt =
      typeof input.startedAt === 'string' && input.startedAt !== ''
        ? input.startedAt
        : new Date().toISOString();
    const startedMs = Date.parse(startedAt);
    if (!Number.isFinite(startedMs)) throw errors.schema('Invalid startedAt.');

    const endedAt =
      typeof input.endedAt === 'string' && input.endedAt !== '' ? input.endedAt : null;

    const turnsRaw = input.turns;
    if (turnsRaw !== undefined && !Array.isArray(turnsRaw)) {
      throw errors.schema('turns must be an array.');
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
      expiresAt: new Date(startedMs + RETENTION_MS).toISOString(),
    };
  }

  async create(input: TranscriptCreateInput, residentSub: string): Promise<string> {
    const conversation = this.buildConversation(input, residentSub);
    await this.store.create(conversation);
    return conversation.conversationId;
  }

  async list(residentSub: string, filter: ConversationQuery): Promise<Conversation[]> {
    return this.store.listOrdered(residentSub, filter);
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
