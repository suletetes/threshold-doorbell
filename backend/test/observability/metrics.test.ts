import { describe, it, expect } from 'vitest';
import { InMemoryMetricsSink } from '../../src/observability/metrics.js';

describe('InMemoryMetricsSink (Task 28, design.md §10)', () => {
  it('records latency observations and summarizes them', () => {
    const m = new InMemoryMetricsSink();
    m.observe('g1a_webhook_to_push_ms', 800);
    m.observe('g1a_webhook_to_push_ms', 1200);
    const s = m.latency('g1a_webhook_to_push_ms');
    expect(s).not.toBeNull();
    expect(s!.count).toBe(2);
    expect(s!.min).toBe(800);
    expect(s!.max).toBe(1200);
    expect(s!.avg).toBe(1000);
  });

  it('bounds retained observations so memory cannot grow without bound (HIGH-21)', () => {
    const m = new InMemoryMetricsSink();
    for (let i = 0; i < 5000; i += 1) {
      m.observe('g2_partial_latency_ms', i);
    }
    const s = m.latency('g2_partial_latency_ms');
    expect(s).not.toBeNull();
    // Capped at 1024 and keeps the most recent observations.
    expect(s!.count).toBe(1024);
    expect(s!.max).toBe(4999);
  });

  it('records all four latency goals G1a/G1b/G2/G3 and webhook ack', () => {
    const m = new InMemoryMetricsSink();
    m.observe('g1a_webhook_to_push_ms', 1);
    m.observe('g1b_open_to_first_caption_ms', 2);
    m.observe('g2_partial_latency_ms', 3);
    m.observe('g3_tap_to_audio_ms', 4);
    m.observe('webhook_ack_ms', 5);
    expect(m.latency('g1a_webhook_to_push_ms')!.count).toBe(1);
    expect(m.latency('g1b_open_to_first_caption_ms')!.count).toBe(1);
    expect(m.latency('g2_partial_latency_ms')!.count).toBe(1);
    expect(m.latency('g3_tap_to_audio_ms')!.count).toBe(1);
    expect(m.latency('webhook_ack_ms')!.count).toBe(1);
  });

  it('drops non-finite and negative latency values', () => {
    const m = new InMemoryMetricsSink();
    m.observe('g2_partial_latency_ms', Number.NaN);
    m.observe('g2_partial_latency_ms', -5);
    m.observe('g2_partial_latency_ms', Infinity);
    expect(m.latency('g2_partial_latency_ms')).toBeNull();
  });

  it('increments counters and ignores non-positive increments', () => {
    const m = new InMemoryMetricsSink();
    m.increment('refresh');
    m.increment('refresh', 2);
    m.increment('refresh', 0);
    m.increment('refresh', -1);
    expect(m.counter('refresh')).toBe(3);
  });

  it('computes probe success rate from success/failure counters', () => {
    const m = new InMemoryMetricsSink();
    expect(m.probeSuccessRate()).toBeNull(); // no probes yet
    m.increment('probe_success', 3);
    m.increment('probe_failure', 1);
    expect(m.probeSuccessRate()).toBe(0.75);
  });

  it('computes Captions-Only session share', () => {
    const m = new InMemoryMetricsSink();
    expect(m.captionsOnlyShare()).toBeNull();
    m.increment('session_captions_only', 1);
    m.increment('session_two_way', 3);
    expect(m.captionsOnlyShare()).toBe(0.25);
  });

  it('tracks injection failure, bedrock fallback, and schema-validation counters', () => {
    const m = new InMemoryMetricsSink();
    m.increment('injection_failure');
    m.increment('bedrock_fallback');
    m.increment('schema_validation_failure', 2);
    expect(m.counter('injection_failure')).toBe(1);
    expect(m.counter('bedrock_fallback')).toBe(1);
    expect(m.counter('schema_validation_failure')).toBe(2);
  });

  it('reset clears everything', () => {
    const m = new InMemoryMetricsSink();
    m.increment('refresh');
    m.observe('g2_partial_latency_ms', 10);
    m.reset();
    expect(m.counter('refresh')).toBe(0);
    expect(m.latency('g2_partial_latency_ms')).toBeNull();
  });
});
