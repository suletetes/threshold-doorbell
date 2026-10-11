// Webhook processing service (Task 5, FR-3.1, FR-3.2, FR-3.3). Parses the Ring
// webhook payload through validation, dedupes by requestId via conditional put,
// and returns whether a push should be enqueued. The route acknowledges 200
// FIRST, then calls enqueuePush asynchronously so the 5 s budget is never at
// risk (design.md §4). residentSub for the push is resolved server-side.

import { randomUUID } from 'node:crypto';
import { errors } from '../domain/errors.js';
import type { BoundingBox, DoorEvent, EventType } from '../domain/types.js';
import type { EventStorePort } from './stores.js';
import type { PushMessage, PushPort } from './push.js';

interface RawWebhook {
  request_id?: unknown;
  event_type?: unknown;
  device_id?: unknown;
  timestamp?: unknown;
  confidence?: unknown;
  bounding_box?: unknown;
  thumbnail_url?: unknown;
  // residentSub is resolved from the device -> account mapping server-side; a
  // client/webhook-supplied resident identifier is never trusted (FR-8.7).
}

const EVENT_TYPES: readonly EventType[] = ['motion_detected', 'person_detected'];

/**
 * LOW-29: a webhook thumbnail_url is only trusted when it is an HTTPS URL on a
 * Ring-owned host. Anything else (a foreign host, http, a javascript: or data:
 * URL) is dropped to null rather than stored and later handed to a client,
 * which prevents the webhook from steering the app at an attacker URL.
 *
 * L-2: '.amazonaws.com' is a deliberately BROAD suffix. The exact Ring/S3
 * bucket host that serves event thumbnails is not known in this environment (no
 * Ring Partner access; no fixture carries a concrete thumbnail host), and S3
 * thumbnail URLs are commonly served from a bucket under *.amazonaws.com. The
 * breadth is acceptable TODAY because: (1) the webhook is HMAC-authenticated
 * over timestamp.body, so only Ring can supply a thumbnail_url at all, and
 * (2) sanitizeThumbnailUrl already requires https: and drops anything that is
 * not a parseable HTTPS URL. BEFORE GO-LIVE this suffix MUST be narrowed to the
 * specific Ring S3 bucket host(s) (for example
 * 'ring-event-thumbnails.s3.amazonaws.com') once Ring's actual thumbnail host
 * is known, so a compromised unrelated amazonaws.com host cannot be referenced.
 */
const ALLOWED_THUMBNAIL_HOST_SUFFIXES = ['.ring.com', '.amazonaws.com'];

function sanitizeThumbnailUrl(value: unknown): string | null {
  if (typeof value !== 'string' || value === '') return null;
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return null;
  }
  if (url.protocol !== 'https:') return null;
  const host = url.hostname.toLowerCase();
  const allowed = ALLOWED_THUMBNAIL_HOST_SUFFIXES.some(
    (suffix) => host === suffix.slice(1) || host.endsWith(suffix),
  );
  return allowed ? url.toString() : null;
}

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

function parseBoundingBox(v: unknown): BoundingBox | null {
  if (!isObject(v)) return null;
  if (
    typeof v.x === 'number' &&
    typeof v.y === 'number' &&
    typeof v.width === 'number' &&
    typeof v.height === 'number'
  ) {
    return { x: v.x, y: v.y, width: v.width, height: v.height };
  }
  return null;
}

/**
 * Validate and normalize a raw Ring webhook body into a DoorEvent. Throws
 * `schema` on a structurally invalid payload (the route maps this to a 400,
 * distinct from the 401 signature failure). requestId is the idempotency key.
 */
export function parseWebhook(raw: unknown): DoorEvent {
  if (!isObject(raw)) throw errors.schema('Malformed webhook payload.');
  const w = raw as RawWebhook;

  if (typeof w.request_id !== 'string' || w.request_id === '') {
    throw errors.schema('Missing request_id.');
  }
  if (typeof w.event_type !== 'string' || !EVENT_TYPES.includes(w.event_type as EventType)) {
    throw errors.schema('Unknown event_type.');
  }
  if (typeof w.device_id !== 'string' || w.device_id === '') {
    throw errors.schema('Missing device_id.');
  }
  const timestamp =
    typeof w.timestamp === 'string' && w.timestamp !== ''
      ? w.timestamp
      : new Date().toISOString();

  // LOW-32: a confidence outside [0,1] (or non-finite) is a contract violation,
  // not a value to store verbatim. Reject it rather than persist a bad number.
  let confidence: number | null = null;
  if (w.confidence !== undefined && w.confidence !== null) {
    if (typeof w.confidence !== 'number' || !Number.isFinite(w.confidence) || w.confidence < 0 || w.confidence > 1) {
      throw errors.schema('Webhook confidence out of range.');
    }
    confidence = w.confidence;
  }

  return {
    eventId: randomUUID(),
    requestId: w.request_id,
    // Placeholder; the owning resident is resolved server-side from the
    // device->account mapping in WebhookService.record (never from the body).
    residentSub: '',
    type: w.event_type as EventType,
    deviceId: w.device_id,
    timestamp,
    confidence,
    boundingBox: parseBoundingBox(w.bounding_box),
    // LOW-29: only keep a thumbnail URL on an allowlisted Ring host over HTTPS.
    thumbnailUrl: sanitizeThumbnailUrl(w.thumbnail_url),
    processedAt: null,
  };
}

/**
 * The residentSub used to quarantine an event whose device is not mapped to any
 * resident (LOW-30). It is an explicit, non-empty marker so the event is never
 * silently stored under '' (which would be unreachable and unerasable) and is
 * never confused with a real resident.
 */
export const UNMAPPED_RESIDENT = '__unmapped__';

export interface WebhookOutcome {
  /** true when this was the first time we saw this requestId. */
  firstDelivery: boolean;
  event: DoorEvent;
}

export class WebhookService {
  constructor(
    private readonly events: EventStorePort,
    private readonly push: PushPort,
    private readonly resolveResident: (deviceId: string) => Promise<string | null>,
  ) {}

  /**
   * Idempotently record the event. Resolves the owning resident from the
   * device->account mapping server-side (never from the webhook body, FR-8.7)
   * and stamps it on the event so the /events feed can scope reads per resident
   * (AT-19). Returns whether this was the first delivery (so the route can
   * decide whether to enqueue a push). This runs BEFORE the 200 is sent and is
   * cheap (a resolve plus a single conditional put).
   */
  async record(event: DoorEvent): Promise<WebhookOutcome> {
    const residentSub = await this.resolveResident(event.deviceId);
    // LOW-30: an unmapped device is quarantined under an explicit marker, never
    // stored under '' (which would be orphaned and unerasable).
    const scoped: DoorEvent = { ...event, residentSub: residentSub ?? UNMAPPED_RESIDENT };
    const result = await this.events.putIfAbsent(scoped);
    return { firstDelivery: result.created, event: result.event };
  }

  /**
   * Deliver the push for a first-delivery event. Called asynchronously AFTER the
   * 200 acknowledgement. Never throws into the request path; a delivery failure
   * is a surfaced result (the app falls back to the FR-3.5 poll), never silent.
   */
  async enqueuePush(event: DoorEvent): Promise<boolean> {
    // A quarantined (unmapped) event has no real owner, so never push it.
    if (event.residentSub === UNMAPPED_RESIDENT) return false;
    // The event already carries its server-resolved owner (set in record());
    // fall back to a fresh resolve for events built outside that path.
    const residentSub =
      event.residentSub !== '' ? event.residentSub : await this.resolveResident(event.deviceId);
    if (!residentSub || residentSub === UNMAPPED_RESIDENT) return false;
    const message: PushMessage = {
      residentSub,
      type: event.type,
      timestamp: event.timestamp,
      deviceId: event.deviceId,
      thumbnailUrl: event.thumbnailUrl,
    };
    const result = await this.push.send(message);
    return result.delivered;
  }
}
