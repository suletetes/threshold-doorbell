import { describe, it, expect } from 'vitest';
import { containsForbiddenDash, stripDashes } from '../../src/domain/ui-copy.js';

describe('ui-copy dash hygiene (NFR-10)', () => {
  it('detects em and en dashes', () => {
    expect(containsForbiddenDash('one \u2014 two')).toBe(true);
    expect(containsForbiddenDash('one \u2013 two')).toBe(true);
    expect(containsForbiddenDash('one - two')).toBe(false);
    expect(containsForbiddenDash('plain ascii')).toBe(false);
  });

  it('replaces dashes with a spaced hyphen and collapses spaces', () => {
    expect(stripDashes('One moment\u2014please')).toBe('One moment - please');
    expect(stripDashes('Come back \u2013 later')).toBe('Come back - later');
    expect(containsForbiddenDash(stripDashes('a\u2014b\u2013c'))).toBe(false);
  });

  it('is idempotent and safe on plain strings', () => {
    expect(stripDashes('nothing to change')).toBe('nothing to change');
    expect(stripDashes(stripDashes('a\u2014b'))).toBe('a - b');
  });
});
