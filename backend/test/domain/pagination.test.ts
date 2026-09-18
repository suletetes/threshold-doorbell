import { describe, it, expect } from 'vitest';
import {
  decodeCursor,
  encodeCursor,
  normalizeLimit,
  paginate,
} from '../../src/domain/pagination.js';
import { PAGINATION_DEFAULT_LIMIT, PAGINATION_MAX_LIMIT } from '../../src/domain/types.js';

describe('pagination', () => {
  describe('normalizeLimit', () => {
    it('defaults when absent or empty', () => {
      expect(normalizeLimit(undefined)).toBe(PAGINATION_DEFAULT_LIMIT);
      expect(normalizeLimit(null)).toBe(PAGINATION_DEFAULT_LIMIT);
      expect(normalizeLimit('')).toBe(PAGINATION_DEFAULT_LIMIT);
    });
    it('clamps to max', () => {
      expect(normalizeLimit(1000)).toBe(PAGINATION_MAX_LIMIT);
      expect(normalizeLimit('9999')).toBe(PAGINATION_MAX_LIMIT);
    });
    it('rejects non-positive and non-numeric values to the default', () => {
      expect(normalizeLimit(0)).toBe(PAGINATION_DEFAULT_LIMIT);
      expect(normalizeLimit(-5)).toBe(PAGINATION_DEFAULT_LIMIT);
      expect(normalizeLimit('abc')).toBe(PAGINATION_DEFAULT_LIMIT);
    });
    it('accepts a valid value', () => {
      expect(normalizeLimit(10)).toBe(10);
      expect(normalizeLimit('42')).toBe(42);
    });
  });

  describe('cursor encode/decode', () => {
    it('round-trips an offset', () => {
      const c = encodeCursor(25);
      expect(decodeCursor(c)).toBe(25);
    });
    it('treats absent cursor as offset 0', () => {
      expect(decodeCursor(undefined)).toBe(0);
      expect(decodeCursor(null)).toBe(0);
      expect(decodeCursor('')).toBe(0);
    });
    it('returns null for a malformed cursor', () => {
      expect(decodeCursor('not-a-valid-cursor!!')).toBeNull();
      expect(decodeCursor(encodeCursor(-1))).toBeNull();
    });
  });

  describe('paginate', () => {
    const data = Array.from({ length: 10 }, (_, i) => i);
    it('returns first page with a nextCursor', () => {
      const page = paginate(data, 3, 0);
      expect(page.items).toEqual([0, 1, 2]);
      expect(page.nextCursor).not.toBeNull();
      expect(decodeCursor(page.nextCursor)).toBe(3);
    });
    it('walks pages with a stable cursor', () => {
      const p1 = paginate(data, 4, 0);
      const p2 = paginate(data, 4, decodeCursor(p1.nextCursor)!);
      const p3 = paginate(data, 4, decodeCursor(p2.nextCursor)!);
      expect(p1.items).toEqual([0, 1, 2, 3]);
      expect(p2.items).toEqual([4, 5, 6, 7]);
      expect(p3.items).toEqual([8, 9]);
      expect(p3.nextCursor).toBeNull();
    });
    it('handles offset past the end', () => {
      const page = paginate(data, 5, 100);
      expect(page.items).toEqual([]);
      expect(page.nextCursor).toBeNull();
    });
    it('handles an empty set', () => {
      const page = paginate([], 5, 0);
      expect(page.items).toEqual([]);
      expect(page.nextCursor).toBeNull();
    });
  });
});
