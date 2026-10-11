// Metrics port and in-memory fixture sink (Task 28, NFR-3, design.md §10).
//
// The design lists these metrics: G1a, G1b, G2, G3, probe success rate,
// Captions-Only session share, injection failure rate, Bedrock fallback rate,
// webhook acknowledgement time, refresh count, and schema-validation failure
// count. They fall into two shapes: latency timings (histograms, ms) and event
// counters (occurrences). This module defines a MetricsPort behind which a real
// CloudWatch adapter or the in-memory fixture sink sits, so metric recording is
// unit-testable without AWS and no PII ever reaches a metric label.
//
// SECURITY: metrics carry ONLY numbers and a small allowlist of names. They
// never carry transcript text, tokens, residentSub, or request bodies (NFR-3).

/** Latency metrics recorded as timings in milliseconds (design.md §10). */
export type LatencyMetric =
  | 'g1a_webhook_to_push_ms'
  | 'g1b_open_to_first_caption_ms'
  | 'g2_partial_latency_ms'
  | 'g3_tap_to_audio_ms'
  | 'webhook_ack_ms';

/** Counter metrics recorded as occurrences (design.md §10). */
export type CounterMetric =
  | 'probe_success'
  | 'probe_failure'
  | 'session_captions_only'
  | 'session_two_way'
  | 'injection_failure'
  | 'bedrock_fallback'
  | 'refresh'
  | 'schema_validation_failure';

export interface MetricsPort {
  /** Record a latency observation (ms). Non-finite or negative values are dropped. */
  observe(metric: LatencyMetric, valueMs: number): void;
  /** Increment a counter by [by] (default 1). */
  increment(metric: CounterMetric, by?: number): void;
}

/** A recorded latency observation and a counter snapshot. */
export interface LatencySummary {
  count: number;
  sum: number;
  min: number;
  max: number;
  /** Simple mean; the real adapter emits percentiles server-side. */
  avg: number;
  values: number[];
}

/**
 * In-memory metrics sink for tests and the demo debug overlay. Holds counters
 * and latency observations so a test can assert a metric was recorded and that
 * no forbidden data leaked into a metric.
 */
/**
 * HIGH-21: the in-memory sink is the only metrics sink in fixture mode, so an
 * unbounded per-metric observation array would grow without bound over a long
 * run. Cap the retained observations per metric; a real adapter would flush to
 * CloudWatch and keep nothing. Metrics carry only numbers, never PII.
 */
const MAX_RETAINED_OBSERVATIONS = 1024;

export class InMemoryMetricsSink implements MetricsPort {
  private readonly counters = new Map<CounterMetric, number>();
  private readonly latencies = new Map<LatencyMetric, number[]>();

  observe(metric: LatencyMetric, valueMs: number): void {
    if (!Number.isFinite(valueMs) || valueMs < 0) return;
    const arr = this.latencies.get(metric) ?? [];
    arr.push(valueMs);
    // HIGH-21: drop the oldest observations past the cap so memory is bounded.
    if (arr.length > MAX_RETAINED_OBSERVATIONS) {
      arr.splice(0, arr.length - MAX_RETAINED_OBSERVATIONS);
    }
    this.latencies.set(metric, arr);
  }

  increment(metric: CounterMetric, by = 1): void {
    if (!Number.isFinite(by) || by <= 0) return;
    this.counters.set(metric, (this.counters.get(metric) ?? 0) + by);
  }

  /** Current value of a counter (0 if never incremented). */
  counter(metric: CounterMetric): number {
    return this.counters.get(metric) ?? 0;
  }

  /** Summary of a latency metric, or null if never observed. */
  latency(metric: LatencyMetric): LatencySummary | null {
    const values = this.latencies.get(metric);
    if (!values || values.length === 0) return null;
    const sum = values.reduce((a, b) => a + b, 0);
    return {
      count: values.length,
      sum,
      min: Math.min(...values),
      max: Math.max(...values),
      avg: sum / values.length,
      values: [...values],
    };
  }

  /**
   * Derived rate helpers for the design.md §10 ratios.
   * Probe success rate = successes / (successes + failures); null when no probes.
   */
  probeSuccessRate(): number | null {
    const s = this.counter('probe_success');
    const f = this.counter('probe_failure');
    const total = s + f;
    return total === 0 ? null : s / total;
  }

  /** Captions-Only session share = captions-only / all sessions; null when none. */
  captionsOnlyShare(): number | null {
    const c = this.counter('session_captions_only');
    const t = this.counter('session_two_way');
    const total = c + t;
    return total === 0 ? null : c / total;
  }

  /** Reset all recorded metrics (test helper). */
  reset(): void {
    this.counters.clear();
    this.latencies.clear();
  }
}
