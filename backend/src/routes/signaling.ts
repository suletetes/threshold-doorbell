// WS /signaling (Task 7, FR-4.1, FR-4.6, FR-4.7; AT-3, AT-11). The signaling
// broker relays a WHEP SDP offer from the WebView peer to Ring and returns the
// SDP answer plus the Ring session URL. Exactly one live session exists per
// resident (FR-4.7); a second concurrent attempt is closed with 4409. The
// session URL is released when the socket closes or times out (FR-4.3).
//
// Close codes (design.md §4):
//   4401 unauthorized          - missing/invalid session credential
//   4408 timeout               - no offer received within the offer window
//   4409 session_already_active- resident already holds a live session
//
// Protocol on the wire (JSON text frames):
//   client -> { "type": "offer", "deviceId": string, "sdp": string }
//   server -> { "type": "answer", "sdpAnswer": string, "sessionUrl": string }
//   client -> { "type": "end" }            (explicit end; also closes on disconnect)
//   server -> { "type": "error", "code": string, "message": string } (then close)

import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { WebSocket } from '@fastify/websocket';
import { SESSION_COOKIE, verifySession, type SessionClaims } from '../security/session.js';
import { SessionAlreadyActiveError, SignalingService } from '../services/signaling-service.js';

/** Close codes used by the signaling broker (design.md §4). */
export const SIGNALING_CLOSE = {
  unauthorized: 4401,
  timeout: 4408,
  sessionAlreadyActive: 4409,
} as const;

/** How long the broker waits for the client's first offer before closing 4408. */
export const OFFER_TIMEOUT_MS = 10_000;

interface OfferMessage {
  type: 'offer';
  deviceId: string;
  sdp: string;
}

export async function registerSignalingRoutes(app: FastifyInstance): Promise<void> {
  const service = new SignalingService(app.container.ringSignaling);
  // Expose for tests and for other routes that must know the single-session state.
  app.decorate('signalingService', service);

  app.get('/signaling', { websocket: true }, (socket: WebSocket, request: FastifyRequest) => {
    const claims = authenticate(request, app.container.config.sessionSecret);
    if (!claims) {
      // Send a typed error frame then close 4401 so the app runs the unified
      // auth-recovery flow (FR-1.5). Deferred so the client has attached its
      // listeners before the frame and close arrive.
      setImmediate(() => {
        safeSend(socket, {
          type: 'error',
          code: 'unauthorized',
          message: 'You need to sign in to continue.',
        });
        socket.close(SIGNALING_CLOSE.unauthorized, 'unauthorized');
      });
      return;
    }
    const residentSub = claims.sub;

    let settled = false; // an offer was processed (answer sent or rejected)
    let opened = false; // this socket owns the resident's active session

    // 4408: close if no offer arrives within the window.
    const timeout = setTimeout(() => {
      if (settled) return;
      safeSend(socket, { type: 'error', code: 'timeout', message: 'No offer received.' });
      socket.close(SIGNALING_CLOSE.timeout, 'offer timeout');
    }, OFFER_TIMEOUT_MS);

    socket.on('message', (raw: Buffer | ArrayBuffer | Buffer[]) => {
      void handleMessage(raw);
    });

    socket.on('close', () => {
      clearTimeout(timeout);
      // Release the Ring session URL on disconnect (FR-4.3). Only this socket's
      // owner releases, so a rejected 4409 attempt never closes the incumbent.
      if (opened) {
        void service.close(residentSub);
      }
    });

    async function handleMessage(raw: Buffer | ArrayBuffer | Buffer[]): Promise<void> {
      const message = parseMessage(raw);
      if (!message) {
        // Ignore malformed frames rather than crash (FR-17 spirit).
        return;
      }
      if (message.type === 'end') {
        if (opened) {
          await service.close(residentSub);
          opened = false;
        }
        socket.close(1000, 'ended');
        return;
      }
      if (message.type !== 'offer') return;
      if (settled) return; // one offer per socket; ignore duplicates
      settled = true;
      clearTimeout(timeout);

      try {
        const handle = await service.open(residentSub, message.deviceId, message.sdp);
        opened = true;
        safeSend(socket, {
          type: 'answer',
          sdpAnswer: handle.sdpAnswer,
          sessionUrl: handle.sessionUrl,
        });
      } catch (err) {
        if (err instanceof SessionAlreadyActiveError) {
          // FR-4.7: reject the second concurrent session with 4409 and do NOT
          // touch the incumbent session.
          safeSend(socket, {
            type: 'error',
            code: 'session_already_active',
            message: 'A live session is already active.',
          });
          socket.close(SIGNALING_CLOSE.sessionAlreadyActive, 'session_already_active');
          return;
        }
        // Ring relay failure: surface a connect error (FR-4.4) and close normally.
        safeSend(socket, {
          type: 'error',
          code: 'ring_unavailable',
          message: "Couldn't connect to your doorbell.",
        });
        socket.close(1011, 'ring_unavailable');
      }
    }
  });
}

/**
 * Authenticate a WS upgrade. Browsers cannot set the Authorization header on a
 * WebSocket, so the session credential may arrive as the `token` query param,
 * the session cookie, or a Bearer header (used by injectWS tests). residentSub
 * is always derived from the verified credential, never from client input.
 */
function authenticate(request: FastifyRequest, secret: string): SessionClaims | null {
  const query = request.query as { token?: unknown } | undefined;
  const queryToken = typeof query?.token === 'string' ? query.token : undefined;
  const cookieToken = request.cookies?.[SESSION_COOKIE];
  const auth = request.headers.authorization;
  const bearer =
    typeof auth === 'string' && auth.startsWith('Bearer ') ? auth.slice('Bearer '.length) : undefined;
  const token = queryToken ?? bearer ?? cookieToken;
  return verifySession(token, secret);
}

type IncomingMessage = OfferMessage | { type: 'end' };

function parseMessage(raw: Buffer | ArrayBuffer | Buffer[]): IncomingMessage | null {
  try {
    const text = Buffer.isBuffer(raw)
      ? raw.toString('utf8')
      : Array.isArray(raw)
        ? Buffer.concat(raw).toString('utf8')
        : Buffer.from(raw).toString('utf8');
    const parsed = JSON.parse(text) as Record<string, unknown>;
    if (parsed.type === 'end') return { type: 'end' };
    if (
      parsed.type === 'offer' &&
      typeof parsed.deviceId === 'string' &&
      parsed.deviceId !== '' &&
      typeof parsed.sdp === 'string' &&
      parsed.sdp !== ''
    ) {
      return { type: 'offer', deviceId: parsed.deviceId, sdp: parsed.sdp };
    }
    return null;
  } catch {
    return null;
  }
}

function safeSend(socket: WebSocket, payload: unknown): void {
  try {
    socket.send(JSON.stringify(payload));
  } catch {
    // Socket may have closed between the check and the send; ignore.
  }
}
