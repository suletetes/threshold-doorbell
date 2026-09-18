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

  return {
    eventId: randomUUID(),
    requestId: w.request_id,
    type: w.event_type as EventType,
    deviceId: w.device_id,
    timestamp,
    confidence: typeof w.confidence === 'number' ? w.confidence : null,
    boundingBox: parseBoundingBox(w.bounding_box),
    thumbnailUrl: typeof w.thumbnail_url === 'string' ? w.thumbnail_url : null,
    processedAt: null,
  };
}

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
   * Idempotently record the event. Returns whether this was the first delivery
   * (so the route can decide whether to enqueue a push). This runs BEFORE the
   * 200 is sent and is cheap (a single conditional put).
   */
  async record(event: DoorEvent): Promise<WebhookOutcome> {
    const result = await this.events.putIfAbsent(event);
    return { firstDelivery: result.created, event: result.event };
  }

  /**
   * Deliver the push for a first-delivery event. Called asynchronously AFTER the
   * 200 acknowledgement. Never throws into the request path; a delivery failure
   * is a surfaced result (the app falls back to the FR-3.5 poll), never silent.
   */
  async enqueuePush(event: DoorEvent): Promise<boolean> {
    const residentSub = await this.resolveResident(event.deviceId);
    if (!residentSub) return false;
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
