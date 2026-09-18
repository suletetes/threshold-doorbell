// Constant-time HMAC verification for Ring webhooks (FR-3.1, NFR-3, design.md §7).
// Verify over the RAW request body. On mismatch, the caller returns 401 without
// processing or logging the body.

import { createHmac, timingSafeEqual } from 'node:crypto';

/** Compute the hex HMAC-SHA256 of a raw body with the webhook key. */
export function computeSignature(rawBody: string | Buffer, key: string): string {
  return createHmac('sha256', key).update(rawBody).digest('hex');
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
