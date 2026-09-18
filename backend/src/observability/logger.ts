// Structured logging with a redaction allowlist (FR-1.7, NFR-3, design.md §7, §10).
// No PII, tokens, session credentials, transcript text, or request bodies may be
// logged. We enforce this with pino's redact plus an explicit deny-list of keys.

import { pino, type Logger } from 'pino';

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

export function createLogger(level = process.env.LOG_LEVEL ?? 'info'): Logger {
  return pino({
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
  });
}

export function getLogger(): Logger {
  if (singleton === null) singleton = createLogger();
  return singleton;
}

/** Test hook: reset the singleton so a test can inject a custom level. */
export function resetLoggerForTest(): void {
  singleton = null;
}
