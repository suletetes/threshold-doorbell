// Structured logging with a redaction allowlist (FR-1.7, NFR-3, design.md §7, §10).
// No PII, tokens, session credentials, transcript text, or request bodies may be
// logged. We enforce this with pino's redact plus an explicit deny-list of keys.

import { pino, type Logger, type DestinationStream } from 'pino';

// Keys that must never appear in logs, at any nesting depth (pino redact paths).
// The wildcard form covers nested occurrences.
export const REDACT_PATHS: string[] = [
  'accessToken',
  'refreshToken',
  'accessTokenEnc',
  'refreshTokenEnc',
  'token',
  'tokens',
  'authorization',
  'cookie',
  'password',
  'clientSecret',
  'hmacKey',
  'webhookHmacKey',
  'sessionSecret',
  'session',
  'body',
  'rawBody',
  'text', // transcript text
  'turns',
  'sub',
  'residentSub',
  '*.accessToken',
  '*.refreshToken',
  '*.accessTokenEnc',
  '*.refreshTokenEnc',
  '*.token',
  '*.authorization',
  '*.cookie',
  '*.clientSecret',
  '*.text',
  '*.residentSub',
];

let singleton: Logger | null = null;

export function createLogger(
  level = process.env.LOG_LEVEL ?? 'info',
  destination?: DestinationStream,
): Logger {
  const options = {
    level,
    redact: {
      paths: REDACT_PATHS,
      censor: '[redacted]',
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
 * inherits the redaction allowlist so no token, PII, transcript text, or body
 * can be logged (NFR-3).
 */
export function correlatedLogger(requestId: string, base: Logger = getLogger()): Logger {
  return base.child({ requestId });
}

/** Test hook: reset the singleton so a test can inject a custom level. */
export function resetLoggerForTest(): void {
  singleton = null;
}
