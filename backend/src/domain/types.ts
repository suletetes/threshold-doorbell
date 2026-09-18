// Domain types for Threshold. Mirrors design.md §3 (Data models and schema).
// These are the single source of truth for shapes shared across services and routes.

export type DeviceId = string;
export type EventType = 'motion_detected' | 'person_detected';
export type Speaker = 'visitor' | 'resident';
export type TurnSource = 'transcribe' | 'ondevice' | 'template' | 'freetext';
export type CaptionMode = 'clarity' | 'privacy';

export interface BoundingBox {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface Device {
  id: DeviceId;
  name: string;
  capabilities: string[];
  privacyZones: BoundingBox[];
  cachedAt: string; // ISO-8601, TTL 24h
}

export interface DoorEvent {
  eventId: string;
  requestId: string; // idempotency key
  type: EventType;
  deviceId: DeviceId;
  timestamp: string;
  confidence: number | null;
  boundingBox: BoundingBox | null;
  thumbnailUrl: string | null;
  processedAt: string | null;
}

export interface Turn {
  turnId: string;
  speaker: Speaker;
  text: string;
  confidence: number | null; // null when unfinalized (FR-5.7)
  provisional: boolean; // true when persisted unfinalized (FR-5.7)
  timestamp: string;
  source: TurnSource;
}

export interface Conversation {
  conversationId: string;
  deviceId: DeviceId;
  residentSub: string; // ALWAYS server-derived from session (FR-8.7)
  startedAt: string;
  endedAt: string | null;
  mode: CaptionMode;
  outboundAvailable: boolean; // probe result, sticky for session (FR-6.4a/b)
  language: string; // BCP-47, FR-16
  turns: Turn[];
  expiresAt: string; // startedAt + 90d, DynamoDB TTL (FR-8.5)
}

export interface RingTokenRecord {
  // Backend only; never on device (FR-1.6). Token attributes are KMS-encrypted.
  residentSub: string;
  accessTokenEnc: string;
  refreshTokenEnc: string;
  expiresAt: string;
}

// Paginated envelope for all list endpoints (design.md §4, D-10).
export interface Page<T> {
  items: T[];
  nextCursor: string | null;
}

export const PAGINATION_DEFAULT_LIMIT = 25;
export const PAGINATION_MAX_LIMIT = 100;

// The fixed safe-reply set (FR-7.2). Always available, never contains dashes (NFR-10).
export const FIXED_SAFE_REPLIES: readonly string[] = [
  'Please leave it at the door',
  "I can't come to the door right now",
  'Please come back later',
];
