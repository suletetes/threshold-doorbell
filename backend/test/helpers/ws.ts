// WebSocket test helpers around @fastify/websocket's injectWS. They collect the
// next JSON frame and the close event so WS route tests read like request/reply
// tests rather than event soup.

import type { WebSocket } from '@fastify/websocket';

/** Resolve with the next parsed JSON text frame from the socket. */
export function nextJson<T = Record<string, unknown>>(ws: WebSocket): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const onMessage = (data: unknown): void => {
      ws.off('message', onMessage);
      ws.off('close', onClose);
      try {
        resolve(JSON.parse(String(data)) as T);
      } catch (err) {
        reject(err as Error);
      }
    };
    const onClose = (code: number): void => {
      ws.off('message', onMessage);
      ws.off('close', onClose);
      reject(new Error(`socket closed before a message (code ${code})`));
    };
    ws.on('message', onMessage);
    ws.on('close', onClose);
  });
}

/**
 * Poll a predicate until it is true or a timeout elapses. Used to observe
 * server-side effects (session release) that happen after a client close,
 * whose propagation timing through injectWS is not synchronous.
 */
export async function waitFor(
  predicate: () => boolean,
  {
    timeoutMs = 2_000,
    intervalMs = 10,
    message = 'condition not met before timeout',
  }: { timeoutMs?: number; intervalMs?: number; message?: string } = {},
): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (predicate()) return;
    await new Promise((r) => setTimeout(r, intervalMs));
  }
  // A silent return on timeout made every waitFor-based assertion pass even
  // when the awaited server effect never happened (MED-39). Fail loudly
  // instead so a regression that stops releasing the session is caught.
  if (predicate()) return;
  throw new Error(`waitFor: ${message} (waited ${timeoutMs}ms)`);
}

/** Resolve with the close code once the socket closes. */
export function closeCode(ws: WebSocket): Promise<number> {
  return new Promise<number>((resolve) => {
    if (ws.readyState === ws.CLOSED) {
      resolve(1005);
      return;
    }
    ws.on('close', (code: number) => resolve(code));
  });
}

/**
 * Collect frames and the eventual close code. Returns the frames received
 * before close plus the close code. Useful when a handler sends an error frame
 * then closes.
 */
export function collectUntilClose<T = Record<string, unknown>>(
  ws: WebSocket,
): Promise<{ frames: T[]; code: number }> {
  return new Promise((resolve) => {
    const frames: T[] = [];
    ws.on('message', (data: unknown) => {
      try {
        frames.push(JSON.parse(String(data)) as T);
      } catch {
        // ignore non-JSON frames in this helper
      }
    });
    ws.on('close', (code: number) => resolve({ frames, code }));
  });
}
