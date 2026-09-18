import { describe, it, expect } from 'vitest';
import { AsrReplayBuffer, REPLAY_WINDOW_MS } from '../../src/services/asr-replay-buffer.js';
import type { AudioChunk } from '../../src/services/transcribe.js';

function chunk(seq: number): AudioChunk {
  return { pcm: new Uint8Array([seq]), seq };
}

describe('AsrReplayBuffer (Task 8, reconnect <= 2s replay; design.md §6)', () => {
  it('replays chunks added within the window, in order', () => {
    const b = new AsrReplayBuffer();
    b.add(chunk(0), 0);
    b.add(chunk(1), 500);
    b.add(chunk(2), 1500);
    const replay = b.replay(1600);
    expect(replay.map((c) => c.seq)).toEqual([0, 1, 2]);
  });

  it('evicts chunks older than 2 seconds so at most the last window replays', () => {
    const b = new AsrReplayBuffer();
    b.add(chunk(0), 0); // will fall out of the 2s window by t=2100
    b.add(chunk(1), 200);
    b.add(chunk(2), 2050);
    const replay = b.replay(2100);
    // t=0 chunk is older than 2100 - 2000 = 100 cutoff and is evicted.
    expect(replay.map((c) => c.seq)).toEqual([1, 2]);
  });

  it('replays nothing after a long gap (all chunks stale)', () => {
    const b = new AsrReplayBuffer();
    b.add(chunk(0), 0);
    b.add(chunk(1), 100);
    const replay = b.replay(10_000);
    expect(replay).toEqual([]);
    expect(b.size).toBe(0);
  });

  it('honors a custom window', () => {
    const b = new AsrReplayBuffer(1_000);
    b.add(chunk(0), 0);
    b.add(chunk(1), 900);
    b.add(chunk(2), 1100);
    const replay = b.replay(1200);
    expect(replay.map((c) => c.seq)).toEqual([1, 2]);
  });

  it('the default window is 2 seconds', () => {
    expect(REPLAY_WINDOW_MS).toBe(2_000);
  });

  it('clear empties the buffer', () => {
    const b = new AsrReplayBuffer();
    b.add(chunk(0), 0);
    b.clear();
    expect(b.size).toBe(0);
    expect(b.replay(0)).toEqual([]);
  });
});
