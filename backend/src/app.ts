// Fastify app factory. Assembles the error envelope handler, the session auth
// guard, and all routes. Stateless: no per-instance state beyond the container's
// fixtures (design.md §1). The real deployment injects real adapters via config.

import Fastify, { type FastifyInstance, type FastifyReply, type FastifyRequest } from 'fastify';
import { randomUUID } from 'node:crypto';
import cookie from '@fastify/cookie';
import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import staticFiles from '@fastify/static';
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
import { registerDemoHubRoutes, demoRooms } from './routes/demo-hub.js';
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
  // CORS: allow the Vercel visitor page to call the backend from a browser.
  // wsAllowedOrigins already holds the Vercel URL; reuse it here so there is
  // one place to configure allowed origins. Credentials must be true so the
  // session cookie reaches /replies.
  await app.register(cors, {
    origin: (origin, cb) => {
      const allowed: readonly string[] = app.container?.config?.wsAllowedOrigins ?? [];
      // No Origin header = native app (Flutter/curl) = always allowed.
      // Known Vercel origin = allowed. Everything else = rejected.
      cb(null, !origin || allowed.includes(origin));
    },
    methods: ['GET', 'POST', 'OPTIONS'],
    allowedHeaders: [
      'Content-Type',
      'Authorization',
      'X-Ring-Signature',
      'X-Ring-Timestamp',
      'Cookie',
    ],
    credentials: true,
    maxAge: 86400,
  });
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
    //
    // L-1: the `env !== 'local'` key here (and on the oauth.ts cookie `secure`
    // flags) is intentional and relies on a DEPLOYMENT INVARIANT: every non-local
    // environment terminates TLS at the edge (design.md section 5 "Transport:
    // TLS 1.2 or higher" and section 11 "containerized Fastify on AWS"), so the
    // connection the browser made is always HTTPS in staging/demo even though
    // the in-process request Fastify sees may be plain HTTP behind the load
    // balancer. Keying on the actual request.protocol or socket encryption would
    // therefore WRONGLY drop HSTS/secure behind a TLS-terminating proxy. If a
    // future topology does not guarantee TLS at the edge, prefer the forwarded
    // scheme: set HSTS/secure when x-forwarded-proto === 'https' and fall back to
    // env !== 'local'. local/test stay plain HTTP for the loopback harness.
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
    // M-1: there is deliberately NO per-route Fastify body/query schema (see
    // design.md section 9: validation is service-layer by choice so the session
    // guard runs before any payload inspection). A Fastify-native validation
    // error (err.validation) therefore never occurs on this app, so the branch
    // that used to translate it was dead code and has been removed. If a route
    // schema is ever added, its validation error carries a 4xx statusCode and is
    // handled by the generic client-error branch below as a 'schema' envelope.
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
  // Serve the visitor page (phone_doorbell.html) at GET / so the demo works
  // without needing a separate Vercel deployment or Cloudflare tunnel.
  // Same origin as the API → no CORS, no mixed-content, no cert warning.
  // The file is baked into the Docker image at build time from src/public/.
  // In the compiled dist/ tree it lives at dist/public/ (Dockerfile copies it).
  const { fileURLToPath } = await import('node:url');
  const { dirname, join } = await import('node:path');
  const publicDir = join(dirname(fileURLToPath(import.meta.url)), 'public');
  await app.register(staticFiles, {
    root: publicDir,
    prefix: '/',
    index: 'index.html',
  });

  app.get('/health', async () => ({ ok: true }));

  // MED-36: readiness probe. Reports whether the dependencies the service needs
  // to serve traffic are reachable. Each dependency check is an awaited probe
  // with a bounded timeout, so a hung real adapter fails the check (503) rather
  // than hanging /ready. In fixture mode everything is in-process and resolves
  // immediately, so it is ready. Returns 503 when any check fails so the
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

  // Two-phone demo relay (demo/local only). Connects the visitor page and the
  // resident app so ring/caption/reply actually travel between the phones.
  if (container.config.env === 'demo' || container.config.env === 'local') {
    await registerDemoHubRoutes(app);
    // Live status page: which rooms exist and who is connected. Plain HTML so
    // you can open it in a browser during the demo for zero-adb debugging.
    app.get('/demo/status', async (_request, reply) => {
      const rows: string[] = [];
      for (const [deviceId, room] of demoRooms.entries()) {
        rows.push(
          `<tr><td>${deviceId}</td>` +
            `<td>${room.visitor ? 'connected' : '-'}</td>` +
            `<td>${room.resident ? 'connected' : '-'}</td></tr>`,
        );
      }
      const body = rows.length > 0 ? rows.join('') : '<tr><td colspan="3">No active rooms</td></tr>';
      reply.type('text/html').send(
        `<!doctype html><html><head><meta charset="utf-8"><title>Demo hub status</title>` +
          `<meta http-equiv="refresh" content="2">` +
          `<style>body{font-family:system-ui;background:#0f172a;color:#f1f5f9;padding:24px}` +
          `table{border-collapse:collapse;width:100%}th,td{border:1px solid #334155;padding:8px 12px;text-align:left}` +
          `th{background:#1e293b}</style></head><body>` +
          `<h1>Demo hub rooms</h1><p>Auto-refreshes every 2 s.</p>` +
          `<table><tr><th>Device ID (room)</th><th>Visitor (Phone A)</th><th>Resident (Phone B)</th></tr>` +
          `${body}</table></body></html>`,
      );
    });
  }

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

// MED-36: per-dependency readiness probe timeout. A real adapter that hangs
// (an unreachable DynamoDB/KMS endpoint) must fail its check rather than block
// /ready indefinitely, so each probe races against this bound.
const READINESS_CHECK_TIMEOUT_MS = 1000;

/**
 * Run an async readiness probe with a bounded timeout. The probe resolves to
 * ok:true only if it completes before the timeout AND does not throw; a thrown
 * error (adapter unreachable) or a timeout (adapter hung) both yield ok:false.
 * In fixture mode the in-process probe resolves immediately, well inside the
 * bound, so readiness stays green.
 */
async function timedCheck(name: string, probe: () => Promise<unknown>): Promise<ReadinessCheck> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_resolve, reject) => {
    timer = setTimeout(() => reject(new Error(`${name} readiness probe timed out`)), READINESS_CHECK_TIMEOUT_MS);
  });
  try {
    await Promise.race([probe(), timeout]);
    return { name, ok: true };
  } catch {
    return { name, ok: false };
  } finally {
    if (timer) clearTimeout(timer);
  }
}

/**
 * MED-36: readiness checks. Each dependency the service needs to serve traffic
 * is probed with a per-check timeout (timedCheck), so a hung real adapter fails
 * the check instead of hanging /ready. In fixture mode the stores are
 * in-process and resolve immediately, so readiness mirrors liveness; once real
 * adapters land, a failing or hung datastore/token-store probe surfaces here as
 * not-ready (503). Kept separate from /health so the two probes can diverge.
 */
async function runReadinessChecks(container: Container): Promise<ReadinessCheck[]> {
  const checks: ReadinessCheck[] = [];
  // The config is validated at boot; its presence is a cheap, synchronous
  // readiness signal that needs no timeout.
  checks.push({ name: 'config', ok: typeof container.config.env === 'string' });
  // The token store must be reachable to serve any authenticated request. A
  // real adapter that hangs or rejects fails this bounded probe.
  checks.push(
    await timedCheck('tokenStore', () => container.tokenStore.get('__readiness_probe__')),
  );
  return checks;
}
