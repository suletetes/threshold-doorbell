// Fixture Transcribe adapter (Task 8, FR-5.1; AT-4). Deterministically emits a
// partial result (no per-token confidence, provisional per FR-5.3) followed by
// a final result whose tokens carry per-token confidences straddling the 0.6
// threshold (FR-5.3a), so the passthrough and styling contract are testable
// without AWS. Error injection drives the 4500 path; a hang mode lets a test
// drive the reconnect-with-replay behavior.

import type {
  AudioChunk,
  TranscribePort,
  TranscribeResult,
  TranscribeStream,
} from '../transcribe.js';

/** Canonical golden result sequence: one partial, then one final (AT-4). */
export function goldenResults(): TranscribeResult[] {
  return [
    // Partial: whole result provisional, no per-token confidence (FR-5.3).
    {
      isFinal: false,
      transcript: 'delivery for',
      tokens: [
        { text: 'delivery', confidence: null },
        { text: 'for', confidence: null },
      ],
    },
    // Final: per-token confidences, one below 0.6 (de-emphasized), rest normal
    // (FR-5.3a). No dashes in any token (NFR-10).
    {
      isFinal: true,
      transcript: 'delivery for you',
      tokens: [
        { text: 'delivery', confidence: 0.92 },
        { text: 'for', confidence: 0.55 },
        { text: 'you', confidence: 0.81 },
      ],
    },
  ];
}

export class FixtureTranscribeStream implements TranscribeStream {
  private closed = false;
  private readonly queue: TranscribeResult[] = [];
  private resolveNext: ((v: IteratorResult<TranscribeResult>) => void) | null = null;
  private emitted = 0;
  private droppedAt = 0;

  constructor(
    private readonly mode: 'ok' | 'error',
    private readonly script: TranscribeResult[],
    /** If > 0, the stream ends (drops) after emitting this many results. */
    private readonly dropAfter = 0,
    /**
     * HIGH-21/FR-8.3: raw audio is NEVER retained in normal operation. The
     * `received` array stays empty unless a test explicitly opts in via
     * retainAudio, so the fixture cannot grow memory without bound by holding
     * every doorstep PCM chunk. The real adapter must likewise never persist
     * audio.
     */
    readonly received: AudioChunk[] = [],
    private readonly retainAudio = false,
  ) {}

  pushAudio(chunk: AudioChunk): void {
    if (this.closed) return;
    // HIGH-21: only retain audio when a test asked for it; otherwise the chunk
    // is used to drive the result script and immediately discarded (FR-8.3).
    if (this.retainAudio) {
      this.received.push(chunk);
    }
    if (this.mode === 'error') {
      // Signal an engine error by closing the stream; results() ends and the
      // route maps this to a 4500 close.
      this.fail();
      return;
    }
    // Each pushed chunk advances the script by one result (partial, then final).
    const next = this.script[this.emitted];
    if (next !== undefined) {
      this.enqueue(next);
      this.emitted += 1;
      this.droppedAt += 1;
      if (this.dropAfter > 0 && this.droppedAt >= this.dropAfter) {
        // Simulate an upstream drop: end the results iterator without error so
        // the route reconnects and replays the buffered audio (design.md §6).
        this.closed = true;
        this.flushWaiter();
      }
    }
  }

  private failed = false;
  private fail(): void {
    this.failed = true;
    this.flushWaiter();
  }

  private enqueue(result: TranscribeResult): void {
    this.queue.push(result);
    this.flushWaiter();
  }

  private flushWaiter(): void {
    if (this.resolveNext === null) return;
    const resolve = this.resolveNext;
    this.resolveNext = null;
    if (this.queue.length > 0) {
      resolve({ value: this.queue.shift() as TranscribeResult, done: false });
    } else {
      resolve({ value: undefined as unknown as TranscribeResult, done: true });
    }
  }

  async *results(): AsyncGenerator<TranscribeResult> {
    for (;;) {
      if (this.queue.length > 0) {
        yield this.queue.shift() as TranscribeResult;
        continue;
      }
      if (this.closed || this.failed) return;
      const result = await new Promise<TranscribeResult | null>((resolve) => {
        // flushWaiter resolves this with a result or with null when the stream
        // ends (closed/failed) so the generator can terminate.
        this.resolveNext = (v: IteratorResult<TranscribeResult>) =>
          resolve(v.done ? null : v.value);
      });
      if (result === null) return;
      yield result;
    }
  }

  async close(): Promise<void> {
    this.closed = true;
    this.flushWaiter();
  }

  /** Test hook: whether an engine error was signalled. */
  get isFailed(): boolean {
    return this.failed;
  }
}

export class FixtureTranscribe implements TranscribePort {
  private mode: 'ok' | 'error' = 'ok';
  private script: TranscribeResult[] = goldenResults();
  private dropAfter = 0;
  readonly openedLanguages: string[] = [];
  readonly streams: FixtureTranscribeStream[] = [];

  /**
   * HIGH-21/FR-8.3: audio and stream bookkeeping are only retained when a test
   * opts in. In normal operation (the container wires `new FixtureTranscribe()`
   * with no argument) nothing is kept, so the fixture cannot accumulate raw
   * doorstep audio or an unbounded list of streams in process memory.
   */
  constructor(private readonly retainAudio = false) {}

  /** Simulate a Transcribe engine error (route closes 4500). */
  setError(): void {
    this.mode = 'error';
  }

  /** Restore normal deterministic streaming. */
  setOk(): void {
    this.mode = 'ok';
  }

  /**
   * Make the NEXT opened stream drop (end without error) after N results, so
   * the route's reconnect-with-replay path is exercised. Reset to 0 after use
   * so the reconnected stream runs normally.
   */
  setDropAfter(n: number): void {
    this.dropAfter = n;
  }

  /** Override the scripted result sequence for a test. */
  setScript(script: TranscribeResult[]): void {
    this.script = script;
  }

  async open(language: string): Promise<TranscribeStream> {
    const drop = this.dropAfter;
    this.dropAfter = 0; // one-shot: only the first stream drops
    const stream = new FixtureTranscribeStream(this.mode, this.script, drop, [], this.retainAudio);
    // HIGH-21: only keep the language and stream bookkeeping under retainAudio
    // so normal operation does not grow memory with every session.
    if (this.retainAudio) {
      this.openedLanguages.push(language);
      this.streams.push(stream);
    }
    return stream;
  }
}
