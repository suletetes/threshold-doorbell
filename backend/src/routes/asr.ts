// WS /asr/stream (Task 8, FR-5.1, G2; AT-4). Clarity-Mode ASR relay: the app
// streams 16 kHz mono PCM up, the broker relays it to Amazon Transcribe
// streaming and passes partial and final results straight back. On an upstream
// drop the relay reconnects once and replays at most the last 2 seconds of
// buffered audio (design.md §6). The caption mode is fixed for the whole
// session and is NEVER switched mid-session (FR-10.1); if the reconnect fails
// the relay closes 4500 and the app ends captions with a notice.
//
// Close codes (design.md §4):
//   4401 unauthorized
//   4500 transcribe_error
//
// Protocol (JSON text control frames + binary audio frames):
//   client -> { "type": "start", "language": string }
//   client -> binary audio chunk (PCM)         OR  { "type": "audio", "seq": n, "pcm": base64 }
//   server -> { "type": "partial" | "final", "transcript": string, "tokens": [...] }
//   client -> { "type": "stop" }               (also closes on disconnect)
//   server -> { "type": "error", "code": "transcribe_error", "message": string } then close 4500

import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { WebSocket } from '@fastify/websocket';
import { authenticateWs } from '../security/ws-auth.js';
import { AsrReplayBuffer } from '../services/asr-replay-buffer.js';
import type {
  AudioChunk,
  TranscribePort,
  TranscribeResult,
  TranscribeStream,
} from '../services/transcribe.js';

export const ASR_CLOSE = {
  unauthorized: 4401,
  transcribeError: 4500,
} as const;

/** Max reconnect attempts on an upstream drop before giving up (design.md §6). */
export const MAX_RECONNECTS = 1;

interface StartMessage {
  type: 'start';
  language: string;
}

export async function registerAsrRoutes(app: FastifyInstance): Promise<void> {
  const port: TranscribePort = app.container.transcribe;

  app.get('/asr/stream', { websocket: true }, (socket: WebSocket, request: FastifyRequest) => {
    const { sessionSecret, wsAllowedOrigins } = app.container.config;
    if (authenticateWs(request, sessionSecret, wsAllowedOrigins) === null) {
      // Defer so the client has attached its listeners before the error frame
      // and close arrive (the socket resolves to the caller after the upgrade).
      setImmediate(() => {
        safeSend(socket, {
          type: 'error',
          code: 'unauthorized',
          message: 'You need to sign in to continue.',
        });
        socket.close(ASR_CLOSE.unauthorized, 'unauthorized');
      });
      return;
    }

    const relay = new AsrRelay(socket, port);
    socket.on('message', (raw: Buffer | ArrayBuffer | Buffer[], isBinary?: boolean) => {
      void relay.onMessage(raw, isBinary === true);
    });
    socket.on('close', () => {
      void relay.dispose();
    });
  });
}

/**
 * Drives one /asr/stream session: opens the Transcribe stream on `start`,
 * relays audio, pumps results, and reconnects with a bounded replay on drop.
 * The chosen language is fixed once and never re-chosen mid-session (FR-10.1).
 */
export class AsrRelay {
  private stream: TranscribeStream | null = null;
  private language: string | null = null;
  private started = false;
  private opening = false; // stream open in flight; buffer audio until ready
  private disposed = false;
  private seq = 0;
  private reconnects = 0;
  private readonly buffer = new AsrReplayBuffer();
  private readonly pending: Uint8Array[] = []; // audio that arrived before the stream opened
  private queue: Promise<void> = Promise.resolve(); // serialize message handling

  constructor(
    private readonly socket: WebSocket,
    private readonly port: TranscribePort,
    private readonly now: () => number = () => Date.now(),
    private readonly maxReconnects: number = MAX_RECONNECTS,
  ) {}

  /**
   * Handle a frame. Frames are serialized so a `start` fully opens the stream
   * before any following `audio` frame is processed; this preserves ordering
   * even though the socket delivers frames without awaiting our async work.
   */
  onMessage(raw: Buffer | ArrayBuffer | Buffer[], isBinary: boolean): Promise<void> {
    this.queue = this.queue.then(() => this.dispatch(raw, isBinary));
    return this.queue;
  }

  private async dispatch(raw: Buffer | ArrayBuffer | Buffer[], isBinary: boolean): Promise<void> {
    if (this.disposed) return;
    if (isBinary) {
      this.onAudio(toBuffer(raw));
      return;
    }
    const control = parseControl(raw);
    if (!control) return;
    if (control.type === 'start') {
      await this.onStart(control.language);
      return;
    }
    if (control.type === 'stop') {
      await this.dispose();
      this.socket.close(1000, 'stopped');
      return;
    }
    if (control.type === 'audio') {
      this.onAudio(control.pcm);
    }
  }

  private async onStart(language: string): Promise<void> {
    if (this.started) return; // one start per session; the language is fixed
    this.started = true;
    this.opening = true;
    this.language = language;
    try {
      this.stream = await this.port.open(language);
      this.opening = false;
      this.pumpResults(this.stream);
      // Flush any audio that arrived while the stream was opening.
      const buffered = this.pending.splice(0, this.pending.length);
      for (const pcm of buffered) this.feed(pcm);
    } catch {
      this.opening = false;
      this.failTranscribe();
    }
  }

  private onAudio(pcm: Uint8Array): void {
    if (this.disposed) return;
    if (!this.started) return; // audio before start is dropped (no session yet)
    if (this.opening || this.stream === null) {
      // Buffer until the stream is ready so no early speech is lost.
      this.pending.push(pcm);
      return;
    }
    this.feed(pcm);
  }

  private feed(pcm: Uint8Array): void {
    if (this.stream === null) return;
    const chunk: AudioChunk = { pcm, seq: this.seq++ };
    this.buffer.add(chunk, this.now());
    this.stream.pushAudio(chunk);
  }

  /**
   * Consume results from a stream and relay them. When the stream ends without
   * an explicit stop, treat it as an upstream drop and attempt a bounded
   * reconnect with replay. The caption mode is NOT changed (FR-10.1).
   */
  private pumpResults(stream: TranscribeStream): void {
    void (async () => {
      let sawResult = false;
      try {
        for await (const result of stream.results()) {
          sawResult = true;
          this.relayResult(result);
        }
      } catch {
        // fall through to reconnect handling
      }
      if (this.disposed || this.stream !== stream) return;
      // The stream ended on its own: reconnect and replay (design.md §6).
      await this.reconnect(sawResult);
    })();
  }

  private relayResult(result: TranscribeResult): void {
    safeSend(this.socket, {
      type: result.isFinal ? 'final' : 'partial',
      transcript: result.transcript,
      tokens: result.tokens,
    });
  }

  private async reconnect(_sawResult: boolean): Promise<void> {
    if (this.disposed || this.language === null) return;
    if (this.reconnects >= this.maxReconnects) {
      this.failTranscribe();
      return;
    }
    this.reconnects += 1;
    try {
      const next = await this.port.open(this.language);
      this.stream = next;
      // Replay at most the last 2 seconds of buffered audio (design.md §6),
      // then clear the buffer so the SAME audio is never replayed twice on a
      // subsequent reconnect (P2-5). Newly fed audio repopulates the window.
      const replay = this.buffer.replay(this.now());
      for (const chunk of replay) {
        next.pushAudio(chunk);
      }
      this.buffer.clear();
      this.pumpResults(next);
    } catch {
      this.failTranscribe();
    }
  }

  private failTranscribe(): void {
    safeSend(this.socket, {
      type: 'error',
      code: 'transcribe_error',
      message: 'Captions are unavailable right now.',
    });
    this.socket.close(ASR_CLOSE.transcribeError, 'transcribe_error');
    void this.dispose();
  }

  async dispose(): Promise<void> {
    if (this.disposed) return;
    this.disposed = true;
    const stream = this.stream;
    this.stream = null;
    if (stream) await stream.close();
  }
}

type Control =
  | StartMessage
  | { type: 'stop' }
  | { type: 'audio'; pcm: Uint8Array };

function parseControl(raw: Buffer | ArrayBuffer | Buffer[]): Control | null {
  try {
    const parsed = JSON.parse(toBuffer(raw).toString('utf8')) as Record<string, unknown>;
    if (parsed.type === 'start' && typeof parsed.language === 'string' && parsed.language !== '') {
      return { type: 'start', language: parsed.language };
    }
    if (parsed.type === 'stop') return { type: 'stop' };
    if (parsed.type === 'audio' && typeof parsed.pcm === 'string') {
      return { type: 'audio', pcm: new Uint8Array(Buffer.from(parsed.pcm, 'base64')) };
    }
    return null;
  } catch {
    return null;
  }
}

function toBuffer(raw: Buffer | ArrayBuffer | Buffer[]): Buffer {
  if (Buffer.isBuffer(raw)) return raw;
  if (Array.isArray(raw)) return Buffer.concat(raw);
  return Buffer.from(raw);
}

function safeSend(socket: WebSocket, payload: unknown): void {
  try {
    socket.send(JSON.stringify(payload));
  } catch {
    // Socket closed; ignore.
  }
}
