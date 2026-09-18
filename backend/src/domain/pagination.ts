// Opaque, stable cursor pagination (design.md §4, D-10; AT-19).
// Cursors are base64url-encoded so clients treat them as opaque tokens.

import { PAGINATION_DEFAULT_LIMIT, PAGINATION_MAX_LIMIT, Page } from './types.js';

export interface ParsedPageQuery {
  limit: number;
  cursor: string | null;
}

/**
 * Clamp a client-supplied limit into [1, PAGINATION_MAX_LIMIT], defaulting when
 * absent or invalid. Never throws: a bad limit degrades to the default so a
 * list request cannot be turned into a 500 by a stray query value.
 */
export function normalizeLimit(raw: unknown): number {
  if (raw === undefined || raw === null || raw === '') return PAGINATION_DEFAULT_LIMIT;
  const n = typeof raw === 'number' ? raw : Number.parseInt(String(raw), 10);
  if (!Number.isFinite(n) || Number.isNaN(n) || n <= 0) return PAGINATION_DEFAULT_LIMIT;
  return Math.min(Math.trunc(n), PAGINATION_MAX_LIMIT);
}

/** Encode an offset into an opaque cursor. */
export function encodeCursor(offset: number): string {
  return Buffer.from(JSON.stringify({ o: offset }), 'utf8').toString('base64url');
}

/**
 * Decode an opaque cursor to an offset. Returns 0 for an absent cursor and
 * throws nothing for a malformed one (returns null so the caller can 400 or
 * treat it as start-of-list). Guards against negative and non-integer offsets.
 */
export function decodeCursor(cursor: string | null | undefined): number | null {
  if (cursor === undefined || cursor === null || cursor === '') return 0;
  try {
    const json = Buffer.from(cursor, 'base64url').toString('utf8');
    const parsed = JSON.parse(json) as { o?: unknown };
    const offset = typeof parsed.o === 'number' ? parsed.o : Number.NaN;
    if (!Number.isInteger(offset) || offset < 0) return null;
    return offset;
  } catch {
    return null;
  }
}

/**
 * Slice an already-ordered array into a page using an offset cursor. The full
 * ordered set is provided by the caller (fixture store returns everything, real
 * store would use a native cursor). This keeps the pagination contract stable
 * and testable against fixtures.
 */
export function paginate<T>(ordered: readonly T[], limit: number, offset: number): Page<T> {
  const start = Math.min(offset, ordered.length);
  const end = Math.min(start + limit, ordered.length);
  const items = ordered.slice(start, end);
  const nextCursor = end < ordered.length ? encodeCursor(end) : null;
  return { items, nextCursor };
}
