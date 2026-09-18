// ASR reconnect replay buffer (Task 8, design.md §6 "Transcribe WS drop").
// On a Transcribe stream drop the relay reconnects and replays at most the last
// 2 seconds of buffered audio, so a brief upstream blip does not lose speech
// (FR-5.1). The buffer is bounded by wall-clock duration, not chunk count, so it
// holds exactly the replay window regardless of chunk size. Pure logic, unit
// tested; it never persists audio beyond the live replay window (FR-8.3).

import type { AudioChunk } from './transcribe.js';

/** Default replay window: at most 2 seconds (design.md §6). */
export const REPLAY_WINDOW_MS = 2_000;

interface TimedChunk {
  chunk: AudioChunk;
  atMs: number;
}

export class AsrReplayBuffer {
  private readonly chunks: TimedChunk[] = [];

  constructor(private readonly windowMs: number = REPLAY_WINDOW_MS) {}

  /**
   * Record a chunk at time [atMs] and evict anything older than the window so
   * the buffer never grows beyond the last [windowMs] of audio.
   */
  add(chunk: AudioChunk, atMs: number): void {
    this.chunks.push({ chunk, atMs });
    this.evict(atMs);
  }

  /**
   * The chunks to replay after a reconnect at time [nowMs]: the last window of
   * audio in original order. Evicts stale chunks first so a long gap replays
   * nothing rather than ancient audio.
   */
  replay(nowMs: number): AudioChunk[] {
    this.evict(nowMs);
    return this.chunks.map((c) => c.chunk);
  }

  /** Number of chunks currently held (for tests and metrics). */
  get size(): number {
    return this.chunks.length;
  }

  /** Clear the buffer after a successful reconnect has replayed it. */
  clear(): void {
    this.chunks.length = 0;
  }

  private evict(nowMs: number): void {
    const cutoff = nowMs - this.windowMs;
    while (this.chunks.length > 0) {
      const head = this.chunks[0];
      if (head === undefined || head.atMs >= cutoff) break;
      this.chunks.shift();
    }
  }
}
