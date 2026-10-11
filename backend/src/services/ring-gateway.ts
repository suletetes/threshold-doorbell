// RingGateway: applies the Ring reliability policy (design.md §6 error table) on
// top of the RingPort. Token-bucket throttle to stay under 100 rps (FR-2.3,
// NFR-7); on 429 back off with jitter and retry; on 5xx retry at most 2 then
// ring_unavailable; a ring_contract_invalid (FR-17) is propagated unchanged
// (the feature degrades but the process/session survives). This is where the
// single Ring adapter's typed errors are turned into route-ready outcomes.

import { AppError, errors } from '../domain/errors.js';
import type { Device } from '../domain/types.js';
import type { RingPort } from './ring.js';
import { backoffWithJitter, TokenBucket } from './rate-limiter.js';

export interface RingGatewayOptions {
  maxRetries?: number; // 5xx retries (default 2, design.md §6)
  bucket?: TokenBucket;
  // Per-resident bucket parameters for fairness (MED-30). Each resident gets
  // their own bucket so one noisy resident cannot starve the others.
  perResidentCapacity?: number;
  perResidentRefillPerSecond?: number;
  now?: () => number;
  // Injectable sleep so backoff is instant in tests.
  sleep?: (ms: number) => Promise<void>;
  random?: () => number;
}

const defaultSleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

export class RingGateway {
  private readonly bucket: TokenBucket;
  private readonly maxRetries: number;
  private readonly sleep: (ms: number) => Promise<void>;
  private readonly random: () => number;
  private readonly now: () => number;
  private readonly perResidentCapacity: number;
  private readonly perResidentRefillPerSecond: number;
  private readonly residentBuckets = new Map<string, TokenBucket>();

  constructor(
    private readonly ring: RingPort,
    opts: RingGatewayOptions = {},
  ) {
    this.bucket =
      opts.bucket ?? new TokenBucket({ capacity: 100, refillPerSecond: 100 });
    this.maxRetries = opts.maxRetries ?? 2;
    this.sleep = opts.sleep ?? defaultSleep;
    this.random = opts.random ?? Math.random;
    this.now = opts.now ?? Date.now;
    // A per-resident share well under the global 100 rps so no single resident
    // can monopolise the global bucket (MED-30, NFR-7).
    this.perResidentCapacity = opts.perResidentCapacity ?? 10;
    this.perResidentRefillPerSecond = opts.perResidentRefillPerSecond ?? 10;
  }

  private residentBucket(residentSub: string): TokenBucket {
    let bucket = this.residentBuckets.get(residentSub);
    if (!bucket) {
      bucket = new TokenBucket({
        capacity: this.perResidentCapacity,
        refillPerSecond: this.perResidentRefillPerSecond,
        now: this.now,
      });
      this.residentBuckets.set(residentSub, bucket);
    }
    return bucket;
  }

  /**
   * List devices with throttle + retry policy. A token is taken PER ATTEMPT
   * (MED-30), from both the resident's own bucket (fairness) and the global
   * bucket (the 100 rps cap), so a retry never buys extra upstream calls for
   * free. Throws rate_limited when a bucket is exhausted, ring_unavailable after
   * exhausting 5xx retries, or ring_contract_invalid immediately on drift.
   */
  async listDevices(residentSub: string, accessToken: string): Promise<Device[]> {
    return this.run(residentSub, () => this.ring.listDevices(accessToken));
  }

  private async run<T>(residentSub: string, op: () => Promise<T>): Promise<T> {
    const residentBucket = this.residentBucket(residentSub);

    let attempt = 0;
    // Total attempts = 1 + maxRetries. Each attempt costs one token from the
    // per-resident bucket AND one from the global bucket (MED-30).
    for (;;) {
      if (!residentBucket.tryRemove() || !this.bucket.tryRemove()) {
        throw errors.rateLimited();
      }
      try {
        return await op();
      } catch (err) {
        const decision = classify(err);
        if (decision === 'contract') {
          // FR-17: degrade the feature, do not retry, propagate the typed error.
          throw err;
        }
        if (decision === 'retryable' && attempt < this.maxRetries) {
          await this.sleep(backoffWithJitter(attempt, 100, 5000, this.random));
          attempt += 1;
          continue;
        }
        if (decision === 'rate_limited' && attempt < this.maxRetries) {
          // Ring-side 429: back off with jitter and retry.
          await this.sleep(backoffWithJitter(attempt, 200, 5000, this.random));
          attempt += 1;
          continue;
        }
        // Exhausted retries or a non-retryable error.
        if (decision === 'rate_limited') throw errors.rateLimited();
        if (decision === 'retryable') throw errors.ringUnavailable();
        throw err instanceof AppError ? err : errors.ringUnavailable();
      }
    }
  }
}

type Decision = 'contract' | 'rate_limited' | 'retryable' | 'fatal';

function classify(err: unknown): Decision {
  if (err instanceof AppError) {
    switch (err.code) {
      case 'ring_contract_invalid':
        return 'contract';
      case 'rate_limited':
        return 'rate_limited';
      case 'ring_unavailable':
        return 'retryable';
      case 'unauthorized':
        // 401 is handled by RingTokenService (refresh-once); do not retry here.
        return 'fatal';
      default:
        return 'fatal';
    }
  }
  // Unknown transport error: treat as a retryable 5xx.
  return 'retryable';
}
