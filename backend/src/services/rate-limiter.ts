// Token-bucket rate limiter with exponential backoff + jitter (FR-2.3, NFR-7).
// Ring allows at most 100 requests/second; we never exceed that. On 429/5xx the
// caller backs off with jitter. This is a pure, injectable clock/random design
// so it is fully testable without real time.

export interface TokenBucketOptions {
  capacity: number; // max tokens (burst)
  refillPerSecond: number; // sustained rate (<= 100 for Ring, NFR-7)
  now?: () => number; // injectable clock (ms)
}

export class TokenBucket {
  private tokens: number;
  private lastRefill: number;
  private readonly capacity: number;
  private readonly refillPerSecond: number;
  private readonly now: () => number;

  constructor(opts: TokenBucketOptions) {
    if (opts.capacity <= 0) throw new Error('capacity must be > 0');
    if (opts.refillPerSecond <= 0 || opts.refillPerSecond > 100) {
      // Hard cap at Ring's 100 rps (NFR-7); refuse a misconfiguration that
      // could exceed it.
      throw new Error('refillPerSecond must be in (0, 100]');
    }
    this.capacity = opts.capacity;
    this.refillPerSecond = opts.refillPerSecond;
    this.now = opts.now ?? Date.now;
    this.tokens = opts.capacity;
    this.lastRefill = this.now();
  }

  private refill(): void {
    const t = this.now();
    const elapsedSec = (t - this.lastRefill) / 1000;
    if (elapsedSec <= 0) return;
    this.tokens = Math.min(this.capacity, this.tokens + elapsedSec * this.refillPerSecond);
    this.lastRefill = t;
  }

  /** Try to consume one token. Returns true when allowed, false when limited. */
  tryRemove(count = 1): boolean {
    this.refill();
    if (this.tokens >= count) {
      this.tokens -= count;
      return true;
    }
    return false;
  }

  /** Current available tokens (after refill). Exposed for tests/metrics. */
  available(): number {
    this.refill();
    return this.tokens;
  }
}

/**
 * Exponential backoff with full jitter. attempt is 0-based. baseMs doubles each
 * attempt, capped at maxMs; jitter picks a value in [0, computed] using the
 * injected random source. Pure and deterministic under a fixed random.
 */
export function backoffWithJitter(
  attempt: number,
  baseMs = 100,
  maxMs = 5000,
  random: () => number = Math.random,
): number {
  const exp = Math.min(maxMs, baseMs * 2 ** attempt);
  return Math.floor(random() * exp);
}
