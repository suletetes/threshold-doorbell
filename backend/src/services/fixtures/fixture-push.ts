// Fixture push adapter. Records deliveries in memory and can simulate failure
// so the webhook async-push path and the FR-3.5 poll fallback are testable.

import type { PushMessage, PushPort, PushResult } from '../push.js';

/**
 * Default cap on the number of sent messages retained even in retention mode,
 * so a long test run or the demo overlay cannot grow memory without bound
 * (HIGH-21). Normal operation keeps nothing at all.
 */
const DEFAULT_MAX_RETAINED = 100;

export class FixturePush implements PushPort {
  readonly sent: PushMessage[] = [];
  private failNext = false;

  /**
   * HIGH-21: push messages carry resident and device identifiers. In normal
   * operation (the container wires `new FixturePush()`) nothing is retained.
   * Tests opt in with retain=true and the retained list is capped so it never
   * grows without bound.
   */
  constructor(
    private readonly retain = false,
    private readonly maxRetained = DEFAULT_MAX_RETAINED,
  ) {}

  /** Cause the next send() to report delivered: false (simulate FCM failure). */
  failOnce(): void {
    this.failNext = true;
  }

  async send(message: PushMessage): Promise<PushResult> {
    if (this.failNext) {
      this.failNext = false;
      return { delivered: false };
    }
    if (this.retain) {
      this.sent.push({ ...message });
      // Bound the retained history so even retention mode cannot grow forever.
      if (this.sent.length > this.maxRetained) {
        this.sent.splice(0, this.sent.length - this.maxRetained);
      }
    }
    return { delivered: true };
  }
}
