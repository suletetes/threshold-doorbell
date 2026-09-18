// Fixture push adapter. Records deliveries in memory and can simulate failure
// so the webhook async-push path and the FR-3.5 poll fallback are testable.

import type { PushMessage, PushPort, PushResult } from '../push.js';

export class FixturePush implements PushPort {
  readonly sent: PushMessage[] = [];
  private failNext = false;

  /** Cause the next send() to report delivered: false (simulate FCM failure). */
  failOnce(): void {
    this.failNext = true;
  }

  async send(message: PushMessage): Promise<PushResult> {
    if (this.failNext) {
      this.failNext = false;
      return { delivered: false };
    }
    this.sent.push({ ...message });
    return { delivered: true };
  }
}
