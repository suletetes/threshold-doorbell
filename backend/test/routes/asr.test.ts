import { describe, it, expect, afterEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildTestApp, sessionFor } from '../helpers/test-app.js';
import { collectUntilClose, nextJson, waitFor } from '../helpers/ws.js';
import { ASR_CLOSE, ASR_GUARD_CLOSE, AsrRelay } from '../../src/routes/asr.js';
import type { TranscribePort, TranscribeStream } from '../../src/services/transcribe.js';
import type { WebSocket } from '@fastify/websocket';
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
    // Only one language was ever opened: the second start frame was ignored.
    // Assert directly rather than sleeping; the condition is already true by
    // the time both results have been received.
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
    // Wait for the reconnect to actually open a second upstream stream rather
    // than sleeping a fixed 40ms. If the reconnect never happens this throws.
    await waitFor(() => t.transcribe.streams.length >= 2, {
      message: 'the relay never reconnected after the upstream drop',
    });
    ws.send(audioFrame(1)); // fed to the reconnected stream -> final
    // Wait for the final frame to be delivered before closing, so the close
    // cannot race ahead of the final result.
    await waitFor(() => frames.some((f) => f.type === 'final'), {
      message: 'no final caption arrived after the reconnect',
    });
    ws.close();
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

  it('caps concurrent sessions per resident and rejects the overflow (HIGH-22)', async () => {
    const t = await buildTestApp();
    app = t.app;
    // The default limit is 2 concurrent sessions per resident.
    expect(t.config.limits.asrMaxSessionsPerResident).toBe(2);
    const token = sessionFor('resident-cap', t.config.sessionSecret);
    const ws1 = await connect(app, token);
    const ws2 = await connect(app, token);
    // Hold both open (they occupy the two slots). Wait until both upstream
    // streams have actually opened rather than sleeping a fixed interval, so
    // the overflow attempt below genuinely races a full slot set.
    ws1.send(startFrame());
    ws2.send(startFrame());
    await waitFor(() => t.transcribe.streams.length >= 2, {
      message: 'both held sessions never opened their upstream streams',
    });
    // The third concurrent attempt is rejected with the too-many-sessions code.
    const ws3 = await connect(app, token);
    const { frames, code } = await collectUntilClose(ws3);
    expect(code).toBe(ASR_GUARD_CLOSE.tooManySessions);
    expect(frames.some((f) => (f as { code?: string }).code === 'rate_limited')).toBe(true);
    // A different resident is unaffected by this resident's cap.
    const otherToken = sessionFor('resident-cap-other', t.config.sessionSecret);
    const wsOther = await connect(app, otherToken);
    wsOther.send(startFrame());
    wsOther.send(audioFrame(0));
    const partial = await nextJson(wsOther);
    expect(partial).toMatchObject({ type: 'partial' });
    ws1.close();
    ws2.close();
    wsOther.close();
  });

  it('fails the session when the upstream stream does not open within the timeout (HIGH-22)', async () => {
    // Drive AsrRelay directly against a port whose open never resolves. With an
    // open timeout the relay must fail the session (close 4500) instead of
    // holding it open and buffering audio without bound.
    const sent: unknown[] = [];
    let closeCodeSeen: number | null = null;
    const fakeSocket = {
      send: (data: string) => sent.push(JSON.parse(data)),
      close: (code: number) => {
        closeCodeSeen = code;
      },
    } as unknown as WebSocket;
    const neverOpens: TranscribePort = {
      open: () => new Promise<TranscribeStream>(() => {}),
    };
    const relay = new AsrRelay(fakeSocket, neverOpens, () => 0, 1, {
      openTimeoutMs: 20,
      maxPendingFrames: 4,
    });
    await relay.onMessage(
      Buffer.from(JSON.stringify({ type: 'start', language: 'en-US' })),
      false,
    );
    expect(closeCodeSeen).toBe(ASR_CLOSE.transcribeError);
    expect(sent.some((f) => (f as { code?: string }).code === 'transcribe_error')).toBe(true);
    await relay.dispose();
  });

  it('bounds audio buffered before the stream opens and fails past the cap (HIGH-22)', async () => {
    // A controllable open: it resolves only when we allow it, so audio sent
    // during the opening window accumulates in the pending buffer. Past the cap
    // the relay fails the session rather than buffering without bound.
    const sent: unknown[] = [];
    let closeCodeSeen: number | null = null;
    const fakeSocket = {
      send: (data: string) => sent.push(JSON.parse(data)),
      close: (code: number) => {
        closeCodeSeen = code;
      },
    } as unknown as WebSocket;
    const openControl: { resolve: ((s: TranscribeStream) => void) | null } = { resolve: null };
    const slowPort: TranscribePort = {
      open: () =>
        new Promise<TranscribeStream>((resolve) => {
          openControl.resolve = resolve;
        }),
    };
    const cap = 4;
    const relay = new AsrRelay(fakeSocket, slowPort, () => 0, 1, { maxPendingFrames: cap });
    // Begin the start without awaiting (open is pending, so the queue is held).
    const startPromise = relay.onMessage(
      Buffer.from(JSON.stringify({ type: 'start', language: 'en-US' })),
      false,
    );
    // Let onStart run up to its pending open (started=true, opening=true).
    await new Promise((r) => setTimeout(r, 5));
    // Feed cap+1 audio frames directly through onAudioForTest so they land in
    // the pending buffer while opening (bypassing the serial queue that is held
    // behind the pending open).
    for (let i = 0; i <= cap; i += 1) {
      relay.onAudioForTest(new Uint8Array([i]));
    }
    expect(closeCodeSeen).toBe(ASR_CLOSE.transcribeError);
    expect(sent.some((f) => (f as { code?: string }).code === 'transcribe_error')).toBe(true);
    // Let the pending open resolve so the start promise settles and nothing leaks.
    openControl.resolve?.({
      pushAudio: () => {},
      results: async function* () {},
      close: async () => {},
    });
    await startPromise;
    await relay.dispose();
  });

  it('rejects an oversized frame via the WebSocket payload cap (HIGH-22)', async () => {
    const t = await buildTestApp();
    app = t.app;
    // The ws maxPayload is 64 KiB; a frame beyond it is dropped and the socket
    // closes rather than buffering the whole payload.
    expect(t.config.limits.wsMaxPayloadBytes).toBe(64 * 1024);
    const token = sessionFor('resident-payload', t.config.sessionSecret);
    const ws = await connect(app, token);
    ws.send(startFrame());
    const huge = JSON.stringify({
      type: 'audio',
      seq: 0,
      pcm: Buffer.alloc(80 * 1024).toString('base64'),
    });
    const closed = new Promise<number>((resolve) => ws.on('close', (c: number) => resolve(c)));
    ws.send(huge);
    const code = await closed;
    // ws closes with 1009 (message too big) or a 1006 abnormal close.
    expect([1006, 1009]).toContain(code);
  });
});
