// Amazon Transcribe streaming port (Task 8, FR-5.1, G2; AT-4). Isolates the
// Clarity-Mode ASR relay behind one interface so the /asr/stream route never
// speaks to Transcribe directly (ports and adapters, structure.md). The real
// adapter opens a Transcribe streaming WebSocket with partial-results
// stabilization; the fixture emits a deterministic partial-then-final sequence
// with per-token confidences so the passthrough and confidence rules are
// unit-testable without AWS.

/** A single recognized token with its confidence, as emitted by the engine. */
export interface TranscribeToken {
  /** The token text (a word or short fragment). */
  text: string;
  /**
   * Per-token confidence in [0, 1]. Present on FINAL results (FR-5.3a). Partial
   * results carry no per-token confidence, so partial tokens set this to null
   * and the app renders the whole partial provisional (FR-5.3).
   */
  confidence: number | null;
}

/** A caption result relayed to the app (design.md §4 /asr/stream contract). */
export interface TranscribeResult {
  /** false for a partial (provisional) result, true when finalized (FR-5.3a). */
  isFinal: boolean;
  /** The full text of this result. */
  transcript: string;
  /** Per-token breakdown; confidences are null on partials (FR-5.3). */
  tokens: TranscribeToken[];
}

/** An audio chunk pushed from the app (16 kHz mono PCM per ARCH-1). */
export interface AudioChunk {
  /** Raw PCM bytes. Never persisted; used only to feed the engine (FR-8.3). */
  pcm: Uint8Array;
  /** Monotonic sequence number so a reconnect can replay unacknowledged audio. */
  seq: number;
}

/**
 * A live Transcribe streaming session. The route pushes audio chunks and
 * consumes results as an async stream. Closing the session tears down the
 * upstream Transcribe connection.
 */
export interface TranscribeStream {
  /** Push an audio chunk to the engine. */
  pushAudio(chunk: AudioChunk): void;
  /** Async iterator of results (partials then finals). */
  results(): AsyncIterable<TranscribeResult>;
  /** Close the upstream stream and stop emitting results. */
  close(): Promise<void>;
}

export interface TranscribePort {
  /**
   * Open a streaming recognition session for a BCP-47 language. Implementations
   * MUST NOT persist audio (FR-8.3) and MUST surface an error to the caller so
   * the route can close 4500 and, per design.md §6, end captions with a notice
   * WITHOUT switching caption mode mid-session (FR-10.1).
   */
  open(language: string): Promise<TranscribeStream>;
}
