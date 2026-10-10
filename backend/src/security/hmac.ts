// Constant-time HMAC verification for Ring webhooks (FR-3.1, NFR-3, design.md §7).
// Verify over the RAW request body. On mismatch, the caller returns 401 without
// processing or logging the body.

import { createHmac, timingSafeEqual } from 'node:crypto';

/** Default webhook replay window: a signed delivery is valid for +/-5 minutes. */
export const WEBHOOK_REPLAY_WINDOW_MS = 5 * 60 * 1000;

/** Compute the hex HMAC-SHA256 of a raw body with the webhook key. */
export function computeSignature(rawBody: string | Buffer, key: string): string {
  return createHmac('sha256', key).update(rawBody).digest('hex');
}

/**
 * Compute the signature over `timestamp.body` (MED-38). Binding the timestamp
 * into the signed material means an attacker cannot replay an old body under a
 * fresh timestamp, and the server can enforce a replay window.
 */
export function computeTimestampedSignature(
  timestamp: string,
  rawBody: string | Buffer,
  key: string,
): string {
  const body = typeof rawBody === 'string' ? rawBody : rawBody.toString('utf8');
  return createHmac('sha256', key).update(`${timestamp}.${body}`).digest('hex');
}

/**
 * Verify a webhook signature over `timestamp.body` against ANY of the accepted
 * keys (rotation) and within the replay window (MED-38). Returns false for a
 * missing/malformed signature, a missing/invalid or stale timestamp, or when no
 * key matches. The comparison is constant-time.
 */
export function verifyTimestampedSignature(args: {
  timestamp: string | undefined;
  rawBody: string | Buffer;
  providedSignature: string | undefined;
  keys: readonly string[];
  now?: number;
  windowMs?: number;
}): boolean {
  const { timestamp, rawBody, providedSignature, keys } = args;
  const now = args.now ?? Date.now();
  const windowMs = args.windowMs ?? WEBHOOK_REPLAY_WINDOW_MS;

  if (typeof providedSignature !== 'string' || providedSignature === '') return false;
  if (typeof timestamp !== 'string' || timestamp === '') return false;

  // Reject a timestamp outside the replay window (or one that cannot be parsed).
  const ts = Date.parse(timestamp);
  if (!Number.isFinite(ts) || Math.abs(now - ts) > windowMs) return false;

  const provided = providedSignature.startsWith('sha256=')
    ? providedSignature.slice('sha256='.length)
    : providedSignature;

  // Any accepted key may have signed the delivery (rotation overlap).
  let matched = false;
  for (const key of keys) {
    const expected = computeTimestampedSignature(timestamp, rawBody, key);
    const a = Buffer.from(provided, 'utf8');
    const b = Buffer.from(expected, 'utf8');
    if (a.length === b.length && timingSafeEqual(a, b)) {
      matched = true;
    }
  }
  return matched;
}

/**
 * Constant-time comparison of a provided signature against the computed one.
 * Accepts an optional "sha256=" prefix as some providers send. Returns false for
 * any malformed input rather than throwing, so a bad header cannot crash the route.
 */
export function verifySignature(
  rawBody: string | Buffer,
  providedSignature: string | undefined,
  key: string,
): boolean {
  if (typeof providedSignature !== 'string' || providedSignature === '') return false;
  const provided = providedSignature.startsWith('sha256=')
    ? providedSignature.slice('sha256='.length)
    : providedSignature;
  const expected = computeSignature(rawBody, key);

  const a = Buffer.from(provided, 'utf8');
  const b = Buffer.from(expected, 'utf8');
  // Length must match for timingSafeEqual; a length difference is a mismatch,
  // but we still run a constant-time compare against a fixed-length buffer to
  // avoid leaking length via early return timing.
  if (a.length !== b.length) {
    // Compare expected against itself to keep timing uniform, then return false.
    timingSafeEqual(b, b);
    return false;
  }
  return timingSafeEqual(a, b);
}
