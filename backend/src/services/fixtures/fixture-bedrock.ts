// Fixture Bedrock adapter (Task 10, FR-7). Deterministic suggestions, with hooks
// to simulate timeout and error so the fixed-safe-set fallback is testable.

import type { BedrockPort, SmartReplyRequest } from '../bedrock.js';

export class FixtureBedrock implements BedrockPort {
  private mode: 'ok' | 'error' | 'hang' = 'ok';

  /** Simulate a Bedrock error (rejects). */
  setError(): void {
    this.mode = 'error';
  }

  /** Simulate a Bedrock hang (never resolves until aborted by the timeout). */
  setHang(): void {
    this.mode = 'hang';
  }

  /** Restore normal deterministic responses. */
  setOk(): void {
    this.mode = 'ok';
  }

  async suggest(request: SmartReplyRequest, signal: AbortSignal): Promise<string[]> {
    if (this.mode === 'error') {
      throw new Error('bedrock unavailable');
    }
    if (this.mode === 'hang') {
      return new Promise<string[]>((_resolve, reject) => {
        if (signal.aborted) {
          reject(new Error('aborted'));
          return;
        }
        signal.addEventListener('abort', () => reject(new Error('aborted')), { once: true });
      });
    }
    // Deterministic, contextual, dash-free suggestions capped at 3.
    const text = request.visitorText.toLowerCase();
    const out: string[] = [];
    if (text.includes('package') || text.includes('delivery')) {
      out.push('Please leave it at the door');
    }
    if (text.includes('who') || text.includes('name')) {
      out.push('Who is this please');
    }
    out.push('One moment please');
    return out.slice(0, 3);
  }
}
