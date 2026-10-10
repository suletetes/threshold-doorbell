import { describe, it, expect, afterEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildTestApp, sessionFor } from '../helpers/test-app.js';
import { decodeState } from '../../src/security/oauth-state.js';
import { fixtureResidentSub } from '../../src/services/fixtures/fixture-ring.js';
import { SESSION_COOKIE, verifySession } from '../../src/security/session.js';

let app: FastifyInstance | undefined;
afterEach(async () => {
  if (app) await app.close();
  app = undefined;
});

describe('OAuth routes (Task 3, AT-1, AT-12)', () => {
  it('GET /oauth/start redirects to Ring authorize with PKCE + state', async () => {
    const t = await buildTestApp();
    app = t.app;
    const res = await app.inject({ method: 'GET', url: '/oauth/start' });
    expect(res.statusCode).toBe(302);
    const location = res.headers.location as string;
    const url = new URL(location);
    expect(url.searchParams.get('response_type')).toBe('code');
    expect(url.searchParams.get('code_challenge_method')).toBe('S256');
    expect(url.searchParams.get('code_challenge')).toBeTruthy();
    // state is a valid signed transaction carrying the verifier.
    const state = url.searchParams.get('state')!;
    expect(decodeState(state, t.config.sessionSecret)).not.toBeNull();
  });

  it('GET /oauth/callback rejects a state mismatch and stores no token (FR-1.3)', async () => {
    const t = await buildTestApp();
    app = t.app;
    const res = await app.inject({
      method: 'GET',
      url: '/oauth/callback?code=abc&state=forged-state',
    });
    expect(res.statusCode).toBe(400);
    const body = res.json();
    expect(body.error.code).toBe('state_mismatch');
    expect(body.error.message).toContain('could not be verified');
    expect(t.tokenStore.size()).toBe(0);
  });

  it('GET /oauth/callback exchanges code, stores encrypted tokens, sets session cookie', async () => {
    const t = await buildTestApp();
    app = t.app;
    // First obtain a valid state from /start.
    const start = await app.inject({ method: 'GET', url: '/oauth/start' });
    const state = new URL(start.headers.location as string).searchParams.get('state')!;

    const res = await app.inject({
      method: 'GET',
      url: `/oauth/callback?code=account-1&state=${encodeURIComponent(state)}`,
    });
    expect(res.statusCode).toBe(302);
    expect(res.headers.location).toBe(t.config.appDeepLink);

    // A session cookie is set (the ONLY credential on device, FR-1.6).
    const cookie = res.cookies.find((c) => c.name === SESSION_COOKIE);
    expect(cookie).toBeDefined();
    const claims = verifySession(cookie!.value, t.config.sessionSecret);
    expect(claims).not.toBeNull();

    // Token is stored encrypted; no cleartext access token anywhere (FR-1.6, AT-1).
    expect(t.tokenStore.size()).toBe(1);
    const row = await t.tokenStore.get(claims!.sub);
    expect(row!.accessTokenEnc).not.toContain('access-account-1');
    // The redirect body carries no Ring token.
    expect(JSON.stringify(res.headers)).not.toContain('access-account-1');
  });

  it('GET /oauth/callback fails cleanly when the code is missing', async () => {
    const t = await buildTestApp();
    app = t.app;
    const start = await app.inject({ method: 'GET', url: '/oauth/start' });
    const state = new URL(start.headers.location as string).searchParams.get('state')!;
    const res = await app.inject({
      method: 'GET',
      url: `/oauth/callback?state=${encodeURIComponent(state)}`,
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('code_exchange_failed');
  });

  it('POST /oauth/refresh requires a session (unified recovery, FR-1.5)', async () => {
    const t = await buildTestApp();
    app = t.app;
    const res = await app.inject({ method: 'POST', url: '/oauth/refresh' });
    expect(res.statusCode).toBe(401);
    expect(res.json().error.code).toBe('unauthorized');
  });

  it('POST /oauth/refresh rolls the session forward on success', async () => {
    const t = await buildTestApp();
    app = t.app;
    // Seed a token record for the resident.
    await t.container.ringTokens.persist('resident-account-1', {
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: new Date(Date.now() + 3600_000).toISOString(),
    });
    const token = sessionFor('resident-account-1', t.config.sessionSecret);
    const res = await app.inject({
      method: 'POST',
      url: '/oauth/refresh',
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().expiresAt).toBeTruthy();
    expect(res.cookies.find((c) => c.name === SESSION_COOKIE)).toBeDefined();
  });

  async function login(code: string, secret: string, instance: FastifyInstance): Promise<string> {
    const start = await instance.inject({ method: 'GET', url: '/oauth/start' });
    const state = new URL(start.headers.location as string).searchParams.get('state')!;
    const res = await instance.inject({
      method: 'GET',
      url: `/oauth/callback?code=${encodeURIComponent(code)}&state=${encodeURIComponent(state)}`,
    });
    const cookie = res.cookies.find((c) => c.name === SESSION_COOKIE)!;
    return verifySession(cookie.value, secret)!.sub;
  }

  it('a crafted code cannot select an arbitrary resident sub (CRIT-03, LOW-41)', async () => {
    const t = await buildTestApp();
    app = t.app;
    // The attacker tries to log in with a code shaped to look like a victim's
    // sub. The derived identity is a one-way function of the account seed, so
    // it is NOT `resident-<code>` and cannot be aimed at a chosen resident.
    const sub = await login('resident-account-1', t.config.sessionSecret, app);
    expect(sub).not.toBe('resident-account-1');
    expect(sub).not.toContain('resident-account-1');
    // Identity is never the raw token text or the code.
    expect(sub).toBe(fixtureResidentSub('resident-account-1'));
  });

  it('two distinct accounts logging in never collapse to the same session sub', async () => {
    const t = await buildTestApp();
    app = t.app;
    const subA = await login('account-42', t.config.sessionSecret, app);
    const subB = await login('refresh-account-42', t.config.sessionSecret, app);
    expect(subA).not.toBe(subB);
  });

  it('a refresh keeps the same sub as the original login (P2-2)', async () => {
    const t = await buildTestApp();
    app = t.app;
    // Log in and capture the derived sub.
    const loginSub = await login('account-42', t.config.sessionSecret, app);

    // Refresh using that session; the rolled-forward session must carry the
    // same sub (refresh never re-derives identity from the token string).
    const refresh = await app.inject({
      method: 'POST',
      url: '/oauth/refresh',
      headers: { authorization: `Bearer ${sessionFor(loginSub, t.config.sessionSecret)}` },
    });
    expect(refresh.statusCode).toBe(200);
    const refreshCookie = refresh.cookies.find((c) => c.name === SESSION_COOKIE)!;
    const refreshedSub = verifySession(refreshCookie.value, t.config.sessionSecret)!.sub;
    expect(refreshedSub).toBe(loginSub);
  });

  it('POST /oauth/refresh surfaces refresh_failed via the single recovery path', async () => {
    const t = await buildTestApp();
    app = t.app;
    await t.container.ringTokens.persist('resident-account-1', {
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: new Date(Date.now() + 60_000).toISOString(), // within skew -> refresh
    });
    t.ring.failRefresh();
    const token = sessionFor('resident-account-1', t.config.sessionSecret);
    const res = await app.inject({
      method: 'POST',
      url: '/oauth/refresh',
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(401);
    expect(res.json().error.code).toBe('refresh_failed');
  });
});
