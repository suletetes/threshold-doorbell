// Structured logging with recursive redaction (FR-1.7, NFR-3, design.md §7, §10).
// No PII, tokens, session credentials, transcript text, SDP, OAuth code/state,
// Ring session URLs, or request bodies may be logged. MED-35: pino's fixed
// redact paths only reach a known depth, so a deeply nested token (depth 3+)
// leaked through. Instead we censor the whole log object with a RECURSIVE walk
// that matches a sensitive key at ANY depth before pino serializes it.

import { pino, type Logger, type DestinationStream } from 'pino';

/**
 * Keys whose VALUE must never be logged, matched case-insensitively at any
 * nesting depth (MED-35). Covers tokens/secrets/cookies, the resident subject,
 * and the free-text and protocol fields that can carry visitor content or an
 * exploitable credential: transcript text, visitorText, sdp, OAuth code/state,
 * and the Ring sessionUrl.
 */
export const REDACTED_KEYS: readonly string[] = [
  'accesstoken',
  'refreshtoken',
  'accesstokenenc',
  'refreshtokenenc',
  'token',
  'tokens',
  'authorization',
  'cookie',
  'password',
  'clientsecret',
  'hmackey',
  'webhookhmackey',
  'sessionsecret',
  'session',
  'body',
  'rawbody',
  'text', // transcript text
  'transcript',
  'visitortext',
  'turns',
  'sdp',
  'sdpanswer',
  'sdpoffer',
  'code',
  'state',
  'sessionurl',
  'sub',
  'residentsub',
];

/**
 * The names kept for the backward-compatible REDACT_PATHS export (used by the
 * allowlist guard test). These are the canonical camelCase key names.
 */
export const REDACT_PATHS: readonly string[] = [
  'accessToken',
  'refreshToken',
  'residentSub',
  'text',
  'body',
  'authorization',
  'cookie',
];

const CENSOR = '[redacted]';
// A hard cap on recursion depth so a cyclic or pathological object cannot hang
// the walker; anything past it is dropped.
const MAX_DEPTH = 8;

const redactedSet = new Set(REDACTED_KEYS);

/**
 * Recursively censor any sensitive key at any depth (MED-35). Returns a new
 * value; the input is never mutated. Non-plain objects (Error, Buffer, Date)
 * are passed through so pino's own serializers still handle them.
 */
export function deepRedact(value: unknown, depth = 0): unknown {
  if (depth > MAX_DEPTH) return CENSOR;
  if (Array.isArray(value)) {
    return value.map((v) => deepRedact(v, depth + 1));
  }
  if (value === null || typeof value !== 'object') return value;
  // Leave special objects for pino's serializers (err/req/res) to format.
  if (value instanceof Error || Buffer.isBuffer(value) || value instanceof Date) {
    return value;
  }
  const out: Record<string, unknown> = {};
  for (const [key, v] of Object.entries(value as Record<string, unknown>)) {
    if (redactedSet.has(key.toLowerCase())) {
      out[key] = CENSOR;
    } else {
      out[key] = deepRedact(v, depth + 1);
    }
  }
  return out;
}

let singleton: Logger | null = null;

export function createLogger(
  level = process.env.LOG_LEVEL ?? 'info',
  destination?: DestinationStream,
): Logger {
  const options = {
    level,
    formatters: {
      // MED-35: censor the entire merged log object recursively before pino
      // writes it, so a sensitive key is removed no matter how deeply nested.
      log(obj: Record<string, unknown>): Record<string, unknown> {
        return deepRedact(obj) as Record<string, unknown>;
      },
    },
    // Never serialize raw request/response bodies.
    serializers: {
      req(req: { method?: string; url?: string; id?: string }) {
        return { method: req.method, url: req.url, id: req.id };
      },
      res(res: { statusCode?: number }) {
        return { statusCode: res.statusCode };
      },
    },
  };
  // The destination override lets tests capture output and assert redaction.
  return destination ? pino(options, destination) : pino(options);
}

export function getLogger(): Logger {
  if (singleton === null) singleton = createLogger();
  return singleton;
}

/**
 * A child logger bound to a correlation id. Where a Ring `requestId` is present
 * (the webhook path) it is used as the correlation id so a log line can be tied
 * to the originating event; elsewhere the Fastify request id is used
 * (design.md §10). The requestId itself is not sensitive, but every child still
 * inherits the recursive redaction so no token, PII, transcript text, SDP,
 * OAuth code/state, session URL, or body can be logged (NFR-3).
 */
export function correlatedLogger(requestId: string, base: Logger = getLogger()): Logger {
  return base.child({ requestId });
}

/** Test hook: reset the singleton so a test can inject a custom level. */
export function resetLoggerForTest(): void {
  singleton = null;
}
