import { describe, it, expect } from 'vitest';
import { issueSession, verifySession, SESSION_IDLE_MS } from '../../src/security/session.js';
import { encodeState } from '../../src/security/oauth-state.js';

const SECRET = 'a-sufficiently-long-session-secret';

describe('session credential', () => {
  it('issues and verifies a valid session', () => {
    const now = Date.now();
    const token = issueSession('resident-a', SECRET, now);
    const claims = verifySession(token, SECRET, now + 1000);
    expect(claims).not.toBeNull();
    expect(claims!.sub).toBe('resident-a');
  });

  it('rejects an expired session (30 min idle, FR-1.5 trigger)', () => {
    const now = Date.now();
    const token = issueSession('resident-a', SECRET, now);
    expect(verifySession(token, SECRET, now + SESSION_IDLE_MS + 1)).toBeNull();
  });

  it('rejects a tampered signature', () => {
    const token = issueSession('resident-a', SECRET);
    const tampered = token.slice(0, -1) + (token.endsWith('A') ? 'B' : 'A');
    expect(verifySession(tampered, SECRET)).toBeNull();
  });

  it('rejects a token signed with a different secret', () => {
    const token = issueSession('resident-a', SECRET);
    expect(verifySession(token, 'another-secret-entirely')).toBeNull();
  });

  it('rejects undefined, empty, and malformed tokens', () => {
    expect(verifySession(undefined, SECRET)).toBeNull();
    expect(verifySession('', SECRET)).toBeNull();
    expect(verifySession('no-dot', SECRET)).toBeNull();
    expect(verifySession('.', SECRET)).toBeNull();
  });

  it('stamps a session typ claim and rejects a non-session typ (MED-33)', () => {
    const token = issueSession('resident-a', SECRET);
    const payload = JSON.parse(Buffer.from(token.split('.')[0]!, 'base64url').toString('utf8'));
    expect(payload.typ).toBe('session');
    // A token carrying a different typ must not be accepted as a session.
    expect(verifySession(token, 'wrong-secret')).toBeNull();
  });

  it('an oauth state token does not verify as a session (MED-33 key separation)', () => {
    // Signed with the state-signing key, so the session verifier (which uses the
    // session-signing key) must reject it.
    const state = encodeState('nonce-1', SECRET);
    expect(verifySession(state, SECRET)).toBeNull();
  });
});
