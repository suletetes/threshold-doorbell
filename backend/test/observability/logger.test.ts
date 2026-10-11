import { describe, it, expect } from 'vitest';
import type { DestinationStream } from 'pino';
import { correlatedLogger, createLogger, REDACT_PATHS } from '../../src/observability/logger.js';

/** A capturing pino destination that collects each written JSON line. */
function capture(): { stream: DestinationStream; lines: () => Record<string, unknown>[] } {
  const raw: string[] = [];
  const stream: DestinationStream = {
    write(chunk: string): void {
      raw.push(chunk);
    },
  };
  return {
    stream,
    lines: () =>
      raw
        .join('')
        .split('\n')
        .filter((l) => l.trim() !== '')
        .map((l) => JSON.parse(l) as Record<string, unknown>),
  };
}

describe('Redacting logger (Task 28, NFR-3, design.md §7, §10)', () => {
  it('redacts tokens and secrets, never emitting their plaintext', () => {
    const c = capture();
    const log = createLogger('info', c.stream);
    log.info(
      {
        accessToken: 'super-secret-access',
        refreshToken: 'super-secret-refresh',
        clientSecret: 'ring-client-secret',
        token: 'bearer-xyz',
      },
      'auth event',
    );
    const [line] = c.lines();
    expect(line!.accessToken).toBe('[redacted]');
    expect(line!.refreshToken).toBe('[redacted]');
    expect(line!.clientSecret).toBe('[redacted]');
    expect(line!.token).toBe('[redacted]');
    const serialized = JSON.stringify(line);
    expect(serialized).not.toContain('super-secret-access');
    expect(serialized).not.toContain('super-secret-refresh');
    expect(serialized).not.toContain('ring-client-secret');
    expect(serialized).not.toContain('bearer-xyz');
  });

  it('redacts PII (residentSub/sub) and transcript text', () => {
    const c = capture();
    const log = createLogger('info', c.stream);
    log.info(
      {
        residentSub: 'resident-abc-123',
        sub: 'resident-abc-123',
        text: 'the visitor said something private',
        turns: [{ text: 'private turn text' }],
      },
      'transcript persisted',
    );
    const serialized = JSON.stringify(c.lines()[0]);
    expect(serialized).not.toContain('resident-abc-123');
    expect(serialized).not.toContain('the visitor said something private');
    expect(serialized).not.toContain('private turn text');
  });

  it('redacts request bodies and raw bodies', () => {
    const c = capture();
    const log = createLogger('info', c.stream);
    log.info(
      {
        body: { visitorText: 'secret body content' },
        rawBody: 'raw-webhook-body-bytes',
        cookie: 'threshold_session=abc',
        authorization: 'Bearer leak',
      },
      'request',
    );
    const serialized = JSON.stringify(c.lines()[0]);
    expect(serialized).not.toContain('secret body content');
    expect(serialized).not.toContain('raw-webhook-body-bytes');
    expect(serialized).not.toContain('threshold_session=abc');
    expect(serialized).not.toContain('Bearer leak');
  });

  it('redacts nested token fields (wildcard paths)', () => {
    const c = capture();
    const log = createLogger('info', c.stream);
    log.info({ record: { accessToken: 'nested-secret', text: 'nested transcript' } }, 'nested');
    const serialized = JSON.stringify(c.lines()[0]);
    expect(serialized).not.toContain('nested-secret');
    expect(serialized).not.toContain('nested transcript');
  });

  it('redacts a token nested three levels deep (MED-35 recursive)', () => {
    const c = capture();
    const log = createLogger('info', c.stream);
    log.info({ a: { b: { accessToken: 'DEPTH3-TOKEN' } } }, 'deep');
    const line = c.lines()[0]!;
    const serialized = JSON.stringify(line);
    expect(serialized).not.toContain('DEPTH3-TOKEN');
    // The censor marker is present at the deep location.
    expect((((line.a as Record<string, unknown>).b) as Record<string, unknown>).accessToken).toBe(
      '[redacted]',
    );
  });

  it('redacts sdp, OAuth code/state, sessionUrl, visitorText and transcript (MED-35)', () => {
    const c = capture();
    const log = createLogger('info', c.stream);
    log.info(
      {
        sdp: 'v=0 secret-sdp',
        code: 'oauth-code-abc',
        state: 'oauth-state-xyz',
        sessionUrl: 'https://ring.example/session/secret',
        visitorText: 'the visitor said something private',
        transcript: 'full private transcript',
        nested: { sdpOffer: 'deep-sdp-offer' },
      },
      'signaling',
    );
    const serialized = JSON.stringify(c.lines()[0]);
    expect(serialized).not.toContain('secret-sdp');
    expect(serialized).not.toContain('oauth-code-abc');
    expect(serialized).not.toContain('oauth-state-xyz');
    expect(serialized).not.toContain('ring.example/session/secret');
    expect(serialized).not.toContain('the visitor said something private');
    expect(serialized).not.toContain('full private transcript');
    expect(serialized).not.toContain('deep-sdp-offer');
  });

  it('correlatedLogger stamps every line with the requestId (design.md §10)', () => {
    const c = capture();
    const base = createLogger('info', c.stream);
    const log = correlatedLogger('req-42', base);
    log.info('correlated event');
    expect(c.lines()[0]!.requestId).toBe('req-42');
  });

  it('the allowlist covers the sensitive key families', () => {
    // Guard against accidental removal of a critical redaction path.
    for (const key of ['accessToken', 'refreshToken', 'residentSub', 'text', 'body', 'authorization', 'cookie']) {
      expect(REDACT_PATHS).toContain(key);
    }
  });
});
