import { describe, it, expect } from 'vitest';
import { backoffWithJitter, TokenBucket } from '../../src/services/rate-limiter.js';

describe('TokenBucket (FR-2.3, NFR-7)', () => {
  it('allows up to capacity then blocks', () => {
    const t = 0;
    const bucket = new TokenBucket({ capacity: 3, refillPerSecond: 1, now: () => t });
    expect(bucket.tryRemove()).toBe(true);
    expect(bucket.tryRemove()).toBe(true);
    expect(bucket.tryRemove()).toBe(true);
    expect(bucket.tryRemove()).toBe(false);
  });

  it('refills over time at the configured rate', () => {
    let t = 0;
    const bucket = new TokenBucket({ capacity: 2, refillPerSecond: 10, now: () => t });
    bucket.tryRemove();
    bucket.tryRemove();
    expect(bucket.tryRemove()).toBe(false);
    t = 200; // 0.2s * 10/s = 2 tokens
    expect(bucket.tryRemove()).toBe(true);
    expect(bucket.tryRemove()).toBe(true);
    expect(bucket.tryRemove()).toBe(false);
  });

  it('never lets sustained rate exceed 100 rps (rejects misconfiguration)', () => {
    expect(() => new TokenBucket({ capacity: 10, refillPerSecond: 101 })).toThrow();
    expect(() => new TokenBucket({ capacity: 10, refillPerSecond: 0 })).toThrow();
    // 100 exactly is allowed.
    expect(() => new TokenBucket({ capacity: 10, refillPerSecond: 100 })).not.toThrow();
  });

  it('rejects a non-positive capacity', () => {
    expect(() => new TokenBucket({ capacity: 0, refillPerSecond: 10 })).toThrow();
  });
});

describe('backoffWithJitter', () => {
  it('grows exponentially and is capped', () => {
    // random() = 0.999... approaches the max of the range; use it to observe
    // exponential growth without hitting the exact ceiling floor edge.
    const nearOne = () => 0.9999;
    expect(backoffWithJitter(0, 100, 5000, nearOne)).toBe(99);
    expect(backoffWithJitter(1, 100, 5000, nearOne)).toBe(199);
    expect(backoffWithJitter(2, 100, 5000, nearOne)).toBe(399);
    // Cap kicks in at maxMs.
    expect(backoffWithJitter(20, 100, 5000, nearOne)).toBe(4999);
  });

  it('applies full jitter (0 with random()=0)', () => {
    expect(backoffWithJitter(5, 100, 5000, () => 0)).toBe(0);
  });
});
