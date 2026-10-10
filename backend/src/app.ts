// Fastify app factory. Assembles the error envelope handler, the session auth
// guard, and all routes. Stateless: no per-instance state beyond the container's
// fixtures (design.md §1). The real deployment injects real adapters via config.

import Fastify, { type FastifyInstance, type FastifyReply, type FastifyRequest } from 'fastify';
import { randomUUID } from 'node:crypto';
import cookie from '@fastify/cookie';
import rateLimit from '@fastify/rate-limit';
import websocket from '@fastify/websocket';
import type { Container } from './container.js';
import { AppError, errors } from './domain/errors.js';
import { correlatedLogger } from './observability/logger.js';
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
    // LOW-25: a cryptographically random UUID (not Math.random).
    genReqId: () => randomUUID(),
    logger: false, // logging is handled by our redacting logger where needed
    // MED-29: lower the body limit well below Fastify's 1 MiB default; no
    // legitimate request to this JSON API is this large, so an oversized body
    // is rejected early (as a 4xx, see the error handler) instead of being
    // parsed into memory.
    bodyLimit: container.config.limits.bodyLimitBytes,
  });

  app.decorate('container', container);
  await app.register(cookie);
  // MED-29: app-level HTTP rate limiting. A per-IP window caps request volume so
  // the OAuth, webhook and REST paths cannot be hammered to drive Bedrock and
  // Transcribe cost or CPU/memory exhaustion. The limiter is skipped for the
  // health/readiness probes so an orchestrator is never throttled.
  await app.register(rateLimit, {
    max: container.config.limits.rateLimitMax,
    timeWindow: container.config.limits.rateLimitWindowMs,
    allowList: (request) => request.url === '/health' || request.url === '/ready',
  });
  // WebSocket transport for /signaling and /asr/stream (design.md §4, WSS).
  // HIGH-22: cap the per-message payload (ws default is 100 MiB) so a single
  // oversized audio/text frame cannot exhaust memory.
  await app.register(websocket, {
    options: { maxPayload: container.config.limits.wsMaxPayloadBytes },
  });

  // HIGH-24: request/response access logging through the redacting logger, plus
  // a request-latency observation (MED-36). The logger serializers never emit
  // bodies, tokens, or PII (NFR-3). WebSocket upgrades are excluded (no res).
  app.addHook('onResponse', async (request, reply) => {
    const status = reply.statusCode;
    const log = correlatedLogger(request.id);
    const line = {
      method: request.method,
      url: request.url,
      statusCode: status,
      responseTimeMs: Math.round(reply.elapsedTime),
    };
    if (status >= 500) {
      log.error(line, 'request failed');
    } else {
      log.info(line, 'request completed');
    }
  });

  // LOW-31: no CORS is configured by design. This is a JSON API consumed by the
  // native app over a Bearer token and by the browser-facing OAuth redirect
  // routes only; no cross-origin browser client is allowed, so no
  // Access-Control-Allow-Origin is ever sent. The OAuth routes are still
  // browser-facing, so set HSTS and nosniff on every response via onSend.
  app.addHook('onSend', async (request, reply, payload) => {
    reply.header('x-content-type-options', 'nosniff');
    // HSTS only matters over TLS; outside local the deployment terminates HTTPS.
    if (container.config.env !== 'local') {
      reply.header('strict-transport-security', 'max-age=31536000; includeSubDomains');
    }
    reply.header('x-frame-options', 'DENY');
    return payload;
  });

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
      // HIGH-23: a session issued before an erasure cutoff is denied, so DELETE
      // /me/data takes effect immediately instead of leaving a valid bearer.
      if (await container.sessionInvalidation.isRevoked(claims.sub, claims.iat)) {
        throw errors.unauthorized();
      }
      request.session = claims;
    },
  );

  // Uniform error envelope for every 4xx/5xx (design.md §4).
  app.setErrorHandler((err, request, reply) => {
    const requestId = request.id;
    if (err instanceof AppError) {
      // A ring_contract_invalid is a schema-validation failure against Ring
      // drift (FR-17); count it for the design.md §10 metric.
      if (err.code === 'ring_contract_invalid' || err.code === 'schema') {
        container.metrics.increment('schema_validation_failure');
        correlatedLogger(requestId).warn({ code: err.code }, 'schema validation failure');
      }
      reply.code(err.statusCode).send(err.toEnvelope(requestId));
      return;
    }
    // Fastify schema validation failures map to our `schema` error.
    if ((err as { validation?: unknown }).validation) {
      container.metrics.increment('schema_validation_failure');
      correlatedLogger(requestId).warn('request schema validation failure');
      const schemaErr = errors.schema();
      reply.code(schemaErr.statusCode).send(schemaErr.toEnvelope(requestId));
      return;
    }
    // HIGH-24: a framework-level client error (malformed JSON body, oversized
    // body, unsupported media type) carries a 4xx statusCode. Pass it through as
    // a 4xx `schema` envelope instead of masking it as a 500 `internal`.
    const statusCode = (err as { statusCode?: number }).statusCode;
    if (typeof statusCode === 'number' && statusCode >= 400 && statusCode < 500) {
      const schemaErr = errors.schema();
      reply.code(statusCode).send(schemaErr.toEnvelope(requestId));
      return;
    }
    // A genuine 5xx: log it through the redacting logger (HIGH-24) so a decrypt
    // throw or a RangeError is no longer silent, then return the opaque internal
    // envelope that never leaks internals.
    correlatedLogger(requestId).error({ err }, 'unhandled server error');
    const internal = errors.internal();
    reply.code(internal.statusCode).send(internal.toEnvelope(requestId));
  });

  // 404 in the same envelope.
  app.setNotFoundHandler((request, reply) => {
    const nf = errors.notFound();
    reply.code(nf.statusCode).send(nf.toEnvelope(request.id));
  });

  // Liveness: the process is up and serving. Always 200 while the event loop
  // runs; used by the load balancer target-group health check.
  app.get('/health', async () => ({ ok: true }));

  // MED-36: readiness probe. Reports whether the dependencies the service needs
  // to serve traffic are reachable. In fixture mode everything is in-process so
  // it is ready; a real adapter deployment can extend readinessChecks to ping
  // its datastore and token store. Returns 503 when any check fails so the
  // orchestrator can hold traffic off a not-yet-ready instance.
  app.get('/ready', async (_request, reply) => {
    const checks = await runReadinessChecks(container);
    const ready = checks.every((c) => c.ok);
    reply.code(ready ? 200 : 503).send({ ready, checks });
  });

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

interface ReadinessCheck {
  name: string;
  ok: boolean;
}

/**
 * MED-36: readiness checks. A real-adapter deployment would ping its datastore
 * and token store here; in fixture mode the stores are in-process and always
 * reachable, so readiness mirrors liveness. Kept separate from /health so the
 * two probes can diverge once real adapters land.
 */
async function runReadinessChecks(container: Container): Promise<ReadinessCheck[]> {
  const checks: ReadinessCheck[] = [];
  // The config is validated at boot; its presence is a cheap readiness signal.
  checks.push({ name: 'config', ok: typeof container.config.env === 'string' });
  // The token store must be reachable to serve any authenticated request.
  try {
    await container.tokenStore.get('__readiness_probe__');
    checks.push({ name: 'tokenStore', ok: true });
  } catch {
    checks.push({ name: 'tokenStore', ok: false });
  }
  return checks;
}
