// Push notification port (Task 5/11, FR-3.3). Real adapter uses FCM; fixture
// records deliveries in memory so the webhook async-push path is testable.

import type { EventType } from '../domain/types.js';

export interface PushMessage {
  residentSub: string;
  type: EventType;
  timestamp: string;
  deviceId: string;
  thumbnailUrl: string | null;
}

export interface PushResult {
  delivered: boolean;
}

export interface PushPort {
  /** Deliver an event notification. Failures are surfaced, never silent (FR-3.5). */
  send(message: PushMessage): Promise<PushResult>;
}
