import { describe, it, expect, afterEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildTestApp, sessionFor } from '../helpers/test-app.js';
import { decodeState, OAUTH_STATE_COOKIE } from '../../src/security/oauth-state.js';
import { fixtureResidentSub } from '../../src/services/fixtures/fixture-ring.js';
import { SESSION_COOKIE, verifySession } from '../../src/security/session.js';

let app: FastifyInstance | undefined;
afterEach(async () => {
  if (app) await app.close();
  app = undefined;
});

/** Start the OAuth flow and return the state and the browser-binding cookie. */
async function startOAuth(instance: FastifyInstance): Promise<{ state: string; cookie: string }> {
  const start = await instance.inject({ method: 'GET', url: '/oauth/start' });
  const state = new URL(start.headers.location as string).searchParams.get('state')!;
  const bind = start.cookies.find((c) => c.name === OAUTH_STATE_COOKIE)!;
  return { state, cookie: `${OAUTH_STATE_COOKIE}=${bind.value}` };
}

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
    // state is a valid signed transaction carrying ONLY the nonce.
    const state = url.searchParams.get('state')!;
    expect(decodeState(state, t.config.sessionSecret)).not.toBeNull();
  });

  it('GET /oauth/start binds state to the browser and keeps the PKCE verifier server-side (HIGH-16/17)', async () => {
    const t = await buildTestApp();
    app = t.app;
    const res = await app.inject({ method: 'GET', url: '/oauth/start' });
    // HIGH-16: a state-binding cookie is set, HttpOnly and SameSite=Lax.
    const bind = res.cookies.find((c) => c.name === OAUTH_STATE_COOKIE);
    expect(bind).toBeDefined();
    expect(bind!.httpOnly).toBe(true);
    expect((bind!.sameSite ?? '').toLowerCase()).toBe('lax');
    // HIGH-17: the front-channel state must NOT contain the PKCE verifier.
    const state = new URL(res.headers.location as string).searchParams.get('state')!;
    const decoded = JSON.parse(Buffer.from(state.split('.')[0]!, 'base64url').toString('utf8'));
    expect(decoded.codeVerifier).toBeUndefined();
    expect(JSON.stringify(decoded)).not.toContain('codeVerifier');
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
    // First obtain a valid state + binding cookie from /start.
    const { state, cookie } = await startOAuth(app);

    const res = await app.inject({
      method: 'GET',
      url: `/oauth/callback?code=account-1&state=${encodeURIComponent(state)}`,
      headers: { cookie },
    });
    expect(res.statusCode).toBe(302);
    // HIGH-18: the redirect carries a one-time app code on the deep link.
    const location = res.headers.location as string;
    expect(location.startsWith(t.config.appDeepLink)).toBe(true);
    expect(new URL(location).searchParams.get('code')).toBeTruthy();

    // A session cookie is set (the ONLY credential on device, FR-1.6).
    const sessionCookie = res.cookies.find((c) => c.name === SESSION_COOKIE);
    expect(sessionCookie).toBeDefined();
    const claims = verifySession(sessionCookie!.value, t.config.sessionSecret);
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
    const { state, cookie } = await startOAuth(app);
    const res = await app.inject({
      method: 'GET',
      url: `/oauth/callback?state=${encodeURIComponent(state)}`,
      headers: { cookie },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('code_exchange_failed');
  });

  it('GET /oauth/callback rejects a missing state cookie (HIGH-16)', async () => {
    const t = await buildTestApp();
    app = t.app;
    const { state } = await startOAuth(app);
    // No cookie header: the state is not bound to this browser.
    const res = await app.inject({
      method: 'GET',
      url: `/oauth/callback?code=account-1&state=${encodeURIComponent(state)}`,
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('state_mismatch');
    expect(t.tokenStore.size()).toBe(0);
  });

  it('GET /oauth/callback rejects a mismatched state cookie (HIGH-16)', async () => {
    const t = await buildTestApp();
    app = t.app;
    const { state } = await startOAuth(app);
    const res = await app.inject({
      method: 'GET',
      url: `/oauth/callback?code=account-1&state=${encodeURIComponent(state)}`,
      headers: { cookie: `${OAUTH_STATE_COOKIE}=tampered-binding-value` },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('state_mismatch');
    expect(t.tokenStore.size()).toBe(0);
  });

  it('GET /oauth/callback rejects a replayed state (single-use, HIGH-16)', async () => {
    const t = await buildTestApp();
    app = t.app;
    const { state, cookie } = await startOAuth(app);
    const first = await app.inject({
      method: 'GET',
      url: `/oauth/callback?code=account-1&state=${encodeURIComponent(state)}`,
      headers: { cookie },
    });
    expect(first.statusCode).toBe(302);
    // Replay the exact same state + cookie: the server-side verifier is gone.
    const replay = await app.inject({
      method: 'GET',
      url: `/oauth/callback?code=account-1&state=${encodeURIComponent(state)}`,
      headers: { cookie },
    });
    expect(replay.statusCode).toBe(400);
    expect(replay.json().error.code).toBe('state_mismatch');
    // The replay never created a second token row.
    expect(t.tokenStore.size()).toBe(1);
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
    const { state, cookie } = await startOAuth(instance);
    const res = await instance.inject({
      method: 'GET',
      url: `/oauth/callback?code=${encodeURIComponent(code)}&state=${encodeURIComponent(state)}`,
      headers: { cookie },
    });
    const session = res.cookies.find((c) => c.name === SESSION_COOKIE)!;
    return verifySession(session.value, secret)!.sub;
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

  // HIGH-18: the session reaches the native app via a one-time code, and the
  // provider error path redirects to the deep link instead of a raw 400.
  it('GET /oauth/callback redirects to the deep link with a one-time code (HIGH-18)', async () => {
    const t = await buildTestApp();
    app = t.app;
    const { state, cookie } = await startOAuth(app);
    const res = await app.inject({
      method: 'GET',
      url: `/oauth/callback?code=account-1&state=${encodeURIComponent(state)}`,
      headers: { cookie },
    });
    expect(res.statusCode).toBe(302);
    const location = new URL(res.headers.location as string);
    expect(res.headers.location).toContain(t.config.appDeepLink);
    expect(location.searchParams.get('code')).toBeTruthy();
  });

  it('POST /oauth/exchange redeems the one-time code for a session (HIGH-18)', async () => {
    const t = await buildTestApp();
    app = t.app;
    const { state, cookie } = await startOAuth(app);
    const callback = await app.inject({
      method: 'GET',
      url: `/oauth/callback?code=account-1&state=${encodeURIComponent(state)}`,
      headers: { cookie },
    });
    const appCode = new URL(callback.headers.location as string).searchParams.get('code')!;
    const expectedSub = verifySession(
      callback.cookies.find((c) => c.name === SESSION_COOKIE)!.value,
      t.config.sessionSecret,
    )!.sub;

    const exchange = await app.inject({
      method: 'POST',
      url: '/oauth/exchange',
      payload: { code: appCode },
    });
    expect(exchange.statusCode).toBe(200);
    const sessionToken = exchange.json().session as string;
    expect(verifySession(sessionToken, t.config.sessionSecret)!.sub).toBe(expectedSub);

    // The one-time code is single-use: a replay is rejected.
    const replay = await app.inject({
      method: 'POST',
      url: '/oauth/exchange',
      payload: { code: appCode },
    });
    expect(replay.statusCode).toBe(401);
    expect(replay.json().error.code).toBe('unauthorized');
  });

  it('POST /oauth/exchange rejects a missing or unknown code (HIGH-18)', async () => {
    const t = await buildTestApp();
    app = t.app;
    const missing = await app.inject({ method: 'POST', url: '/oauth/exchange', payload: {} });
    expect(missing.statusCode).toBe(401);
    const unknown = await app.inject({
      method: 'POST',
      url: '/oauth/exchange',
      payload: { code: 'never-issued' },
    });
    expect(unknown.statusCode).toBe(401);
  });

  it('GET /oauth/callback redirects to the deep link with ?error= on a provider error (HIGH-18)', async () => {
    const t = await buildTestApp();
    app = t.app;
    const { state, cookie } = await startOAuth(app);
    const res = await app.inject({
      method: 'GET',
      url: `/oauth/callback?error=access_denied&state=${encodeURIComponent(state)}`,
      headers: { cookie },
    });
    // Not a raw 400 JSON: a 302 to the deep link carrying the error.
    expect(res.statusCode).toBe(302);
    const location = new URL(res.headers.location as string);
    expect(res.headers.location).toContain(t.config.appDeepLink);
    expect(location.searchParams.get('error')).toBe('access_denied');
    // No token was stored on the error path.
    expect(t.tokenStore.size()).toBe(0);
  });
});
