// Fastify app factory. Assembles the error envelope handler, the session auth
// guard, and all routes. Stateless: no per-instance state beyond the container's
// fixtures (design.md §1). The real deployment injects real adapters via config.

import Fastify, { type FastifyInstance, type FastifyReply, type FastifyRequest } from 'fastify';
import cookie from '@fastify/cookie';
import websocket from '@fastify/websocket';
import type { Container } from './container.js';
import { AppError, errors } from './domain/errors.js';
import { SESSION_COOKIE, verifySession, type SessionClaims } from './security/session.js';
import { registerOAuthRoutes } from './routes/oauth.js';
import { registerWebhookRoutes } from './routes/webhook.js';
import { registerDeviceRoutes } from './routes/devices.js';
import { registerEventRoutes } from './routes/events.js';
import { registerTranscriptRoutes } from './routes/transcripts.js';
import { registerReplyRoutes } from './routes/replies.js';
import { registerSignalingRoutes } from './routes/signaling.js';
import { registerAsrRoutes } from './routes/asr.js';
import type { SignalingService } from './services/signaling-service.js';

declare module 'fastify' {
  interface FastifyRequest {
    // The authenticated session, set by requireSession. Never client-supplied.
    session?: SessionClaims;
  }
  interface FastifyInstance {
    container: Container;
    requireSession(request: FastifyRequest, reply: FastifyReply): Promise<void>;
    signalingService: SignalingService;
  }
}

export async function buildApp(container: Container): Promise<FastifyInstance> {
  const app = Fastify({
    // genReqId gives every request a correlation id used as the error requestId
    // and (where present) aligned to the Ring requestId at the webhook route.
    genReqId: () => cryptoRandomId(),
    logger: false, // logging is handled by our redacting logger where needed
  });

  app.decorate('container', container);
  await app.register(cookie);
  // WebSocket transport for /signaling and /asr/stream (design.md §4, WSS).
  await app.register(websocket);

  // Session auth guard (FR-8.7, design.md §7). Derives residentSub from the
  // session credential only. A client-supplied identifier is never trusted.
  app.decorate(
    'requireSession',
    async function requireSession(request: FastifyRequest, _reply: FastifyReply): Promise<void> {
      const bearer = extractBearer(request);
      const cookieToken = request.cookies?.[SESSION_COOKIE];
      const token = bearer ?? cookieToken;
      const claims = verifySession(token, container.config.sessionSecret);
      if (!claims) {
        // A single unified failure signal; the app runs one recovery flow (FR-1.5).
        throw errors.unauthorized();
      }
      request.session = claims;
    },
  );

  // Uniform error envelope for every 4xx/5xx (design.md §4).
  app.setErrorHandler((err, request, reply) => {
    const requestId = request.id;
    if (err instanceof AppError) {
      reply.code(err.statusCode).send(err.toEnvelope(requestId));
      return;
    }
    // Fastify schema validation failures map to our `schema` error.
    if ((err as { validation?: unknown }).validation) {
      const schemaErr = errors.schema();
      reply.code(schemaErr.statusCode).send(schemaErr.toEnvelope(requestId));
      return;
    }
    // Unknown errors never leak internals.
    const internal = errors.internal();
    reply.code(internal.statusCode).send(internal.toEnvelope(requestId));
  });

  // 404 in the same envelope.
  app.setNotFoundHandler((request, reply) => {
    const nf = errors.notFound();
    reply.code(nf.statusCode).send(nf.toEnvelope(request.id));
  });

  app.get('/health', async () => ({ ok: true }));

  await registerOAuthRoutes(app);
  // Encapsulate the webhook so its raw-body content-type parser does not affect
  // JSON parsing on any other route.
  await app.register(async (instance) => {
    await registerWebhookRoutes(instance);
  });
  await registerDeviceRoutes(app);
  await registerEventRoutes(app);
  await registerTranscriptRoutes(app);
  await registerReplyRoutes(app);
  await registerSignalingRoutes(app);
  await registerAsrRoutes(app);

  return app;
}

function extractBearer(request: FastifyRequest): string | undefined {
  const auth = request.headers.authorization;
  if (typeof auth === 'string' && auth.startsWith('Bearer ')) {
    return auth.slice('Bearer '.length);
  }
  return undefined;
}

function cryptoRandomId(): string {
  // 16 hex chars is enough entropy for a correlation id.
  return Math.random().toString(16).slice(2, 10) + Date.now().toString(16);
}
