// P2-5: AsrRelay must replay its <=2s buffer at most ONCE. Before the fix the
// buffer was replayed on reconnect but never cleared, so a second reconnect
// would replay the same audio again (masked in production only because
// MAX_RECONNECTS is 1). Here we drive two reconnects via an injectable budget
// and assert no chunk is replayed twice.

import { describe, it, expect } from 'vitest';
import { AsrRelay } from '../../src/routes/asr.js';
import type {
  AudioChunk,
  TranscribePort,
  TranscribeResult,
  TranscribeStream,
} from '../../src/services/transcribe.js';

// A stream that emits nothing and ends (drops) on the first pushed chunk, so
// the relay reconnects. It records every chunk it receives (including replays).
class DroppingStream implements TranscribeStream {
  readonly received: AudioChunk[] = [];
  private ended = false;
  private resolveEnd: (() => void) | null = null;

  pushAudio(chunk: AudioChunk): void {
    this.received.push(chunk);
    // End the results iterator to simulate an upstream drop.
    this.ended = true;
    if (this.resolveEnd) {
      const r = this.resolveEnd;
      this.resolveEnd = null;
      r();
    }
  }

  async *results(): AsyncGenerator<TranscribeResult> {
    if (this.ended) return;
    await new Promise<void>((resolve) => {
      this.resolveEnd = resolve;
    });
    // Yield nothing; the stream has dropped.
  }

  async close(): Promise<void> {
    this.ended = true;
  }
}

class DroppingPort implements TranscribePort {
  readonly streams: DroppingStream[] = [];
  async open(): Promise<TranscribeStream> {
    const s = new DroppingStream();
    this.streams.push(s);
    return s;
  }
}

// Minimal socket stub.
function fakeSocket(): { send: (p: unknown) => void; close: () => void } {
  return { send: () => undefined, close: () => undefined };
}

describe('AsrRelay replay buffer is cleared after replay (P2-5)', () => {
  it('never replays the same buffered audio twice across reconnects', async () => {
    const port = new DroppingPort();
    // maxReconnects=2 lets us observe a second reconnect; the clock is fixed so
    // nothing is evicted by the 2s window.
    const relay = new AsrRelay(fakeSocket() as never, port, () => 1000, 2);

    await relay.onMessage(Buffer.from(JSON.stringify({ type: 'start', language: 'en-US' })), false);
    // Feed one audio chunk into stream[0]. stream[0] drops -> reconnect #1
    // replays seq 0 into stream[1]. That replay push makes stream[1] drop too ->
    // reconnect #2 (allowed by maxReconnects=2). If the buffer were NOT cleared
    // after the first replay, seq 0 would be replayed a SECOND time into
    // stream[2]; with the fix it is cleared, so stream[2] receives nothing.
    await relay.onMessage(
      Buffer.from(JSON.stringify({ type: 'audio', seq: 0, pcm: Buffer.from([1]).toString('base64') })),
      false,
    );
    // Let all reconnect microtasks settle.
    for (let i = 0; i < 10; i += 1) await new Promise((r) => setImmediate(r));

    await relay.dispose();

    // seq 0 is replayed at most once across every reconnected stream.
    const replayCountOfSeq0 = port.streams
      .slice(1)
      .flatMap((s) => s.received.map((c) => c.seq))
      .filter((seq) => seq === 0).length;
    expect(replayCountOfSeq0).toBe(1);
  });
});
