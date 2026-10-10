import { describe, it, expect, afterEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildTestApp, sessionFor } from '../helpers/test-app.js';
import { collectUntilClose, nextJson } from '../helpers/ws.js';
import { ASR_CLOSE } from '../../src/routes/asr.js';
import { WS_SESSION_PROTOCOL_PREFIX } from '../../src/security/ws-auth.js';

/** Open an /asr/stream WS carrying the session via Sec-WebSocket-Protocol (MED-34). */
function connect(instance: FastifyInstance, token: string) {
  return instance.injectWS('/asr/stream', {
    headers: { 'sec-websocket-protocol': `${WS_SESSION_PROTOCOL_PREFIX}${token}` },
  });
}

let app: FastifyInstance | undefined;
afterEach(async () => {
  if (app) await app.close();
  app = undefined;
});

const SUB = 'resident-asr';

function startFrame(language = 'en-US'): string {
  return JSON.stringify({ type: 'start', language });
}
function audioFrame(seq: number): string {
  // A tiny PCM chunk as base64 (deterministic, never persisted).
  return JSON.stringify({ type: 'audio', seq, pcm: Buffer.from([1, 2, 3, 4]).toString('base64') });
}

describe('WS /asr/stream (Task 8, FR-5.1, G2; AT-4)', () => {
  it('closes 4401 when unauthenticated', async () => {
    const t = await buildTestApp();
    app = t.app;
    const ws = await app.injectWS('/asr/stream');
    const { frames, code } = await collectUntilClose(ws);
    expect(code).toBe(ASR_CLOSE.unauthorized);
    expect(frames[0]).toMatchObject({ type: 'error', code: 'unauthorized' });
  });

  it('passes a partial result straight through, provisional with null token confidences (FR-5.3, AT-4)', async () => {
    const t = await buildTestApp();
    app = t.app;
    const token = sessionFor(SUB, t.config.sessionSecret);
    const ws = await connect(app, token);
    ws.send(startFrame());
    ws.send(audioFrame(0)); // first chunk -> partial
    const partial = await nextJson(ws);
    expect(partial).toMatchObject({ type: 'partial', transcript: 'delivery for' });
    const tokens = (partial as { tokens: Array<{ confidence: number | null }> }).tokens;
    expect(tokens.every((tk) => tk.confidence === null)).toBe(true);
    ws.close();
  });

  it('emits a final result with per-token confidences straddling 0.6 (FR-5.3a, AT-4)', async () => {
    const t = await buildTestApp();
    app = t.app;
    const token = sessionFor(SUB, t.config.sessionSecret);
    const ws = await connect(app, token);
    ws.send(startFrame());
    ws.send(audioFrame(0)); // partial
    await nextJson(ws);
    ws.send(audioFrame(1)); // final
    const final = await nextJson(ws);
    expect(final).toMatchObject({ type: 'final', transcript: 'delivery for you' });
    const confs = (final as { tokens: Array<{ confidence: number }> }).tokens.map((tk) => tk.confidence);
    expect(confs).toEqual([0.92, 0.55, 0.81]);
    // one token below the 0.6 threshold, the rest at/above it
    expect(confs.filter((c) => c < 0.6).length).toBe(1);
    ws.close();
  });

  it('records the requested language and never re-chooses it mid-session (FR-10.1)', async () => {
    const t = await buildTestApp();
    app = t.app;
    const token = sessionFor(SUB, t.config.sessionSecret);
    const ws = await connect(app, token);
    ws.send(startFrame('es-US'));
    ws.send(audioFrame(0));
    await nextJson(ws);
    // A second start frame must be ignored: the language stays fixed.
    ws.send(startFrame('en-US'));
    ws.send(audioFrame(1));
    await nextJson(ws);
    ws.close();
    await new Promise((r) => setTimeout(r, 20));
    expect(t.transcribe.openedLanguages).toEqual(['es-US']);
  });

  it('closes 4500 when the Transcribe engine errors (design.md §6)', async () => {
    const t = await buildTestApp();
    app = t.app;
    t.transcribe.setError();
    const token = sessionFor(SUB, t.config.sessionSecret);
    const ws = await connect(app, token);
    ws.send(startFrame());
    ws.send(audioFrame(0));
    const { frames, code } = await collectUntilClose(ws);
    expect(code).toBe(ASR_CLOSE.transcribeError);
    expect(frames.some((f) => (f as { code?: string }).code === 'transcribe_error')).toBe(true);
  });

  it('reconnects and replays buffered audio on an upstream drop, without switching mode (design.md §6, FR-10.1)', async () => {
    const t = await buildTestApp();
    app = t.app;
    // First stream drops after emitting 1 result (the partial), simulating an
    // upstream Transcribe WS drop. The route must reconnect and replay.
    t.transcribe.setDropAfter(1);
    const token = sessionFor(SUB, t.config.sessionSecret);
    const ws = await connect(app, token);
    const frames: Array<{ type: string }> = [];
    ws.on('message', (d: unknown) => frames.push(JSON.parse(String(d))));
    ws.send(startFrame('en-US'));
    ws.send(audioFrame(0)); // partial, then the first stream drops -> reconnect + replay
    await new Promise((r) => setTimeout(r, 40));
    ws.send(audioFrame(1)); // fed to the reconnected stream -> final
    await new Promise((r) => setTimeout(r, 40));
    ws.close();
    await new Promise((r) => setTimeout(r, 20));
    // The language never changed across the reconnect (FR-10.1): same language,
    // and the stream was reopened (reconnect happened).
    expect(t.transcribe.openedLanguages).toEqual(['en-US', 'en-US']);
    // The reconnected stream received the replayed buffered audio (design.md §6).
    const reconnected = t.transcribe.streams[1];
    expect(reconnected).toBeDefined();
    expect(reconnected!.received.length).toBeGreaterThan(0);
    // We received at least one partial and eventually a final.
    expect(frames.some((f) => f.type === 'partial')).toBe(true);
    expect(frames.some((f) => f.type === 'final')).toBe(true);
  });

  it('ignores a session token passed in the URL query (MED-34)', async () => {
    const t = await buildTestApp();
    app = t.app;
    const token = sessionFor(SUB, t.config.sessionSecret);
    const ws = await app.injectWS(`/asr/stream?token=${encodeURIComponent(token)}`);
    const { code } = await collectUntilClose(ws);
    expect(code).toBe(ASR_CLOSE.unauthorized);
  });

  it('a stop frame closes the stream normally', async () => {
    const t = await buildTestApp();
    app = t.app;
    const token = sessionFor(SUB, t.config.sessionSecret);
    const ws = await connect(app, token);
    ws.send(startFrame());
    ws.send(JSON.stringify({ type: 'stop' }));
    const code = await new Promise<number>((resolve) => ws.on('close', (c: number) => resolve(c)));
    expect(code).toBe(1000);
  });
});
