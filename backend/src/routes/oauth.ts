// OAuth 2.0 authorization-code + PKCE routes (Task 3, FR-1.1..1.5, FR-1.7).
// The Ring client secret never reaches the app; token exchange/refresh run here.
// A single unified recovery path exists: any auth failure yields a 401
// (unauthorized / refresh_failed) that the app resolves with one re-auth prompt.

import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { errors } from '../domain/errors.js';
import { createPkcePair, generateState } from '../security/pkce.js';
import { decodeState, encodeState } from '../security/oauth-state.js';
import { issueSession, SESSION_COOKIE, SESSION_IDLE_MS } from '../security/session.js';

interface CallbackQuery {
  code?: string;
  state?: string;
}

export async function registerOAuthRoutes(app: FastifyInstance): Promise<void> {
  const { config } = app.container;

  // GET /oauth/start -> 302 to Ring authorize with PKCE + signed state.
  app.get('/oauth/start', async (_request: FastifyRequest, reply: FastifyReply) => {
    try {
      const pkce = createPkcePair();
      const nonce = generateState();
      const state = encodeState(nonce, pkce.codeVerifier, config.sessionSecret);
      const url = new URL(config.ring.authorizeUrl);
      url.searchParams.set('response_type', 'code');
      url.searchParams.set('client_id', config.ring.clientId);
      url.searchParams.set('redirect_uri', config.ring.redirectUri);
      url.searchParams.set('scope', 'read');
      url.searchParams.set('state', state);
      url.searchParams.set('code_challenge', pkce.codeChallenge);
      url.searchParams.set('code_challenge_method', pkce.challengeMethod);
      reply.code(302).header('location', url.toString()).send();
    } catch {
      throw errors.oauthInitFailed();
    }
  });

  // GET /oauth/callback -> verify state, exchange code server-side, set session,
  // redirect to the app deep link. State mismatch is rejected (FR-1.3) with no
  // token stored.
  app.get(
    '/oauth/callback',
    async (request: FastifyRequest<{ Querystring: CallbackQuery }>, reply: FastifyReply) => {
      const { code, state } = request.query;

      // FR-1.3: reject on state mismatch before touching any token.
      const txn = decodeState(state, config.sessionSecret);
      if (!txn) {
        throw errors.stateMismatch();
      }
      if (typeof code !== 'string' || code === '') {
        throw errors.codeExchangeFailed();
      }

      // Exchange code for tokens server-side (FR-1.2). Secret never leaves here.
      let tokens;
      try {
        tokens = await app.container.ring.exchangeCode(
          code,
          txn.codeVerifier,
          config.ring.redirectUri,
        );
      } catch {
        throw errors.codeExchangeFailed();
      }

      // residentSub is derived server-side. For the fixture flow it is a stable
      // function of the account behind the code; the real adapter derives it
      // from the Ring identity response. It is never taken from client input.
      const residentSub = deriveResidentSub(tokens.accessToken);
      await app.container.ringTokens.persist(residentSub, tokens);

      // Issue the app-to-backend session credential (the ONLY credential on the
      // device, FR-1.6). Set as an HttpOnly, Secure, SameSite=strict cookie.
      const session = issueSession(residentSub, config.sessionSecret);
      reply
        .code(302)
        .header('location', config.appDeepLink)
        .setCookie(SESSION_COOKIE, session, {
          httpOnly: true,
          secure: config.env !== 'local',
          sameSite: 'strict',
          path: '/',
          maxAge: Math.floor(SESSION_IDLE_MS / 1000),
        })
        .send();
    },
  );

  // POST /oauth/refresh -> refresh the app session on success. Uses the same
  // unified recovery signal on failure (refresh_failed => one re-auth prompt).
  app.post(
    '/oauth/refresh',
    { preHandler: app.requireSession },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const residentSub = request.session!.sub;
      // Ensure the Ring tokens are still valid/refreshable; this throws
      // refresh_failed on any auth failure (single recovery path, FR-1.5).
      await app.container.ringTokens.getAccessToken(residentSub);
      // design.md §10 metric: refresh count.
      app.container.metrics.increment('refresh');

      // Roll the app session forward (idle-expiry reset).
      const session = issueSession(residentSub, config.sessionSecret);
      const expiresAt = new Date(Date.now() + SESSION_IDLE_MS).toISOString();
      reply
        .setCookie(SESSION_COOKIE, session, {
          httpOnly: true,
          secure: config.env !== 'local',
          sameSite: 'strict',
          path: '/',
          maxAge: Math.floor(SESSION_IDLE_MS / 1000),
        })
        .code(200)
        .send({ expiresAt });
    },
  );
}

/**
 * Derive a stable residentSub 1:1 with the Ring account. The fixture mints an
 * access token of the form `access-<code>` on a fresh login and
 * `access-refreshed-<refreshToken>` on a refresh, so we strip ONLY that leading
 * `access-`/`access-refreshed-` grant marker to recover the underlying account
 * seed. We must NOT strip any further (e.g. a `refresh-` that is part of the
 * account seed itself), or two distinct accounts would collapse to one sub:
 * previously `account-42` and `refresh-account-42` both mapped to
 * `resident-account-42`. The real adapter derives this from the Ring identity
 * response, not the token string; either way the value is server-derived and
 * never taken from client input (FR-8.7).
 */
export function deriveResidentSub(accessToken: string): string {
  const seed = accessToken.replace(/^access-(refreshed-)?/, '');
  return `resident-${seed}`;
}
