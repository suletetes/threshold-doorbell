import { describe, it, expect } from 'vitest';
import { FixtureTranscribe } from '../../src/services/fixtures/fixture-transcribe.js';
import type { AudioChunk, TranscribeResult, TranscribeStream } from '../../src/services/transcribe.js';

function chunk(seq: number): AudioChunk {
  return { pcm: new Uint8Array([seq]), seq };
}

async function collect(stream: TranscribeStream, n: number): Promise<TranscribeResult[]> {
  const out: TranscribeResult[] = [];
  for await (const r of stream.results()) {
    out.push(r);
    if (out.length >= n) break;
  }
  return out;
}

describe('FixtureTranscribe (Task 8, FR-5.1; AT-4)', () => {
  it('emits a partial (null token confidences) then a final (per-token confidences)', async () => {
    const t = new FixtureTranscribe();
    const stream = await t.open('en-US');
    stream.pushAudio(chunk(0));
    stream.pushAudio(chunk(1));
    const results = await collect(stream, 2);
    expect(results).toHaveLength(2);
    const [partial, final] = results;
    expect(partial!.isFinal).toBe(false);
    expect(partial!.tokens.every((tk) => tk.confidence === null)).toBe(true);
    expect(final!.isFinal).toBe(true);
    expect(final!.tokens.map((tk) => tk.confidence)).toEqual([0.92, 0.55, 0.81]);
    await stream.close();
  });

  it('records the opened language', async () => {
    const t = new FixtureTranscribe();
    await t.open('es-US');
    expect(t.openedLanguages).toEqual(['es-US']);
  });

  it('ends the results iterator when set to error mode', async () => {
    const t = new FixtureTranscribe();
    t.setError();
    const stream = await t.open('en-US');
    stream.pushAudio(chunk(0));
    const results = await collect(stream, 5);
    // Error mode emits no results; the iterator ends.
    expect(results).toEqual([]);
  });

  it('drops after N results when configured (reconnect path), one-shot', async () => {
    const t = new FixtureTranscribe();
    t.setDropAfter(1);
    const first = await t.open('en-US');
    first.pushAudio(chunk(0));
    const firstResults = await collect(first, 5);
    expect(firstResults).toHaveLength(1); // dropped after the partial
    // The next open is a fresh, non-dropping stream.
    const second = await t.open('en-US');
    second.pushAudio(chunk(1));
    second.pushAudio(chunk(2));
    const secondResults = await collect(second, 2);
    expect(secondResults).toHaveLength(2);
    expect(t.streams[0]!.received).toHaveLength(1);
  });

  it('never persists audio: pushed chunks are only kept in-memory for replay', async () => {
    const t = new FixtureTranscribe();
    const stream = await t.open('en-US');
    stream.pushAudio(chunk(0));
    // The fixture holds chunks only in the received array (test observability),
    // not on disk. There is no filesystem write path here (FR-8.3).
    expect(t.streams[0]!.received.map((c) => c.seq)).toEqual([0]);
  });
});
