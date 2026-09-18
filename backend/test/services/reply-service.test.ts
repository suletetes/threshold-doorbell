import { describe, it, expect } from 'vitest';
import { ReplyService, fixedSet } from '../../src/services/reply-service.js';
import { FixtureBedrock } from '../../src/services/fixtures/fixture-bedrock.js';
import { FIXED_SAFE_REPLIES } from '../../src/domain/types.js';
import { containsForbiddenDash } from '../../src/domain/ui-copy.js';
import type { BedrockPort, SmartReplyRequest } from '../../src/services/bedrock.js';

describe('ReplyService (Task 10, FR-7)', () => {
  it('returns up to 3 contextual suggestions in the happy path', async () => {
    const svc = new ReplyService(new FixtureBedrock());
    const res = await svc.suggest({ visitorText: 'I have a package delivery', language: 'en-US' });
    expect(res.fallback).toBe(false);
    expect(res.suggestions.length).toBeGreaterThan(0);
    expect(res.suggestions.length).toBeLessThanOrEqual(3);
  });

  it('falls back to the fixed safe set on Bedrock error (FR-7.3, AT-7)', async () => {
    const bedrock = new FixtureBedrock();
    bedrock.setError();
    const svc = new ReplyService(bedrock);
    const res = await svc.suggest({ visitorText: 'hi', language: 'en-US' });
    expect(res.fallback).toBe(true);
    expect(res.suggestions).toEqual(FIXED_SAFE_REPLIES.map((s) => s));
  });

  it('falls back within the timeout when Bedrock hangs (FR-7.3, AT-7)', async () => {
    const bedrock = new FixtureBedrock();
    bedrock.setHang();
    const svc = new ReplyService(bedrock, 50); // short timeout for the test
    const start = Date.now();
    const res = await svc.suggest({ visitorText: 'hi', language: 'en-US' });
    expect(res.fallback).toBe(true);
    expect(res.suggestions.length).toBe(3);
    expect(Date.now() - start).toBeLessThan(1000);
  });

  it('caps at 3 and de-dupes suggestions (FR-7.1)', async () => {
    const many: BedrockPort = {
      async suggest(_req: SmartReplyRequest): Promise<string[]> {
        return ['a', 'a', 'b', 'c', 'd', 'e'];
      },
    };
    const svc = new ReplyService(many);
    const res = await svc.suggest({ visitorText: 'x', language: 'en-US' });
    expect(res.suggestions).toEqual(['a', 'b', 'c']);
  });

  it('strips em/en dashes from generated suggestions (NFR-10)', async () => {
    const dashy: BedrockPort = {
      async suggest(): Promise<string[]> {
        return ['One moment \u2014 please', 'Come back \u2013 later'];
      },
    };
    const svc = new ReplyService(dashy);
    const res = await svc.suggest({ visitorText: 'x', language: 'en-US' });
    for (const s of res.suggestions) {
      expect(containsForbiddenDash(s)).toBe(false);
    }
  });

  it('falls back when Bedrock returns only empties', async () => {
    const empties: BedrockPort = {
      async suggest(): Promise<string[]> {
        return ['', '   '];
      },
    };
    const svc = new ReplyService(empties);
    const res = await svc.suggest({ visitorText: 'x', language: 'en-US' });
    expect(res.fallback).toBe(true);
  });

  it('fixedSet is always the three safe replies and dash-free', () => {
    const set = fixedSet();
    expect(set).toHaveLength(3);
    for (const s of set) expect(containsForbiddenDash(s)).toBe(false);
  });
});
