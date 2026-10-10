// OAuth 2.0 authorization-code + PKCE routes (Task 3, FR-1.1..1.5, FR-1.7).
// The Ring client secret never reaches the app; token exchange/refresh run here.
// A single unified recovery path exists: any auth failure yields a 401
// (unauthorized / refresh_failed) that the app resolves with one re-auth prompt.

import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { errors } from '../domain/errors.js';
import { createPkcePair, generateState } from '../security/pkce.js';
import {
  decodeState,
  encodeState,
  hashNonce,
  nonceCookieMatches,
  OAUTH_STATE_COOKIE,
} from '../security/oauth-state.js';
import { issueSession, SESSION_COOKIE, SESSION_IDLE_MS } from '../security/session.js';

interface CallbackQuery {
  code?: string;
  state?: string;
}

// How long a started OAuth transaction stays redeemable (matches the signed
// state TTL in oauth-state.ts): the nonce entry and cookie expire together.
const OAUTH_TXN_TTL_MS = 10 * 60 * 1000;

export async function registerOAuthRoutes(app: FastifyInstance): Promise<void> {
  const { config } = app.container;

  // GET /oauth/start -> 302 to Ring authorize with PKCE + signed state. The PKCE
  // verifier is kept server-side keyed by the nonce (HIGH-17); the state carries
  // only the nonce. An HttpOnly SameSite=Lax cookie holds H(nonce) to bind the
  // state to this browser (HIGH-16).
  app.get('/oauth/start', async (_request: FastifyRequest, reply: FastifyReply) => {
    try {
      const pkce = createPkcePair();
      const nonce = generateState();
      // Keep the verifier server-side, single-use, short-lived (HIGH-17).
      await app.container.oauthTxnStore.put(nonce, pkce.codeVerifier, OAUTH_TXN_TTL_MS);
      const state = encodeState(nonce, config.sessionSecret);
      const url = new URL(config.ring.authorizeUrl);
      url.searchParams.set('response_type', 'code');
      url.searchParams.set('client_id', config.ring.clientId);
      url.searchParams.set('redirect_uri', config.ring.redirectUri);
      url.searchParams.set('scope', 'read');
      url.searchParams.set('state', state);
      url.searchParams.set('code_challenge', pkce.codeChallenge);
      url.searchParams.set('code_challenge_method', pkce.challengeMethod);
      reply
        .code(302)
        .header('location', url.toString())
        .setCookie(OAUTH_STATE_COOKIE, hashNonce(nonce, config.sessionSecret), {
          httpOnly: true,
          secure: config.env !== 'local',
          sameSite: 'lax',
          path: '/',
          maxAge: Math.floor(OAUTH_TXN_TTL_MS / 1000),
        })
        .send();
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
      // HIGH-16: the state must be bound to THIS browser. The cookie holds
      // H(nonce); reject when it is missing or does not match the state nonce.
      const stateCookie = request.cookies?.[OAUTH_STATE_COOKIE];
      if (!nonceCookieMatches(stateCookie, hashNonce(txn.nonce, config.sessionSecret))) {
        throw errors.stateMismatch();
      }
      // HIGH-16/17: redeem the server-side verifier. take() is single-use, so a
      // replayed state finds no verifier and is rejected. Clear the binding
      // cookie now that the transaction is consumed.
      const codeVerifier = await app.container.oauthTxnStore.take(txn.nonce);
      reply.clearCookie(OAUTH_STATE_COOKIE, { path: '/' });
      if (codeVerifier === null) {
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
          codeVerifier,
          config.ring.redirectUri,
        );
      } catch {
        throw errors.codeExchangeFailed();
      }

      // residentSub comes from the provider's identity response carried on the
      // exchanged tokens (fixture: a one-way function of the account; real
      // adapter: the Ring userinfo response). It is NEVER parsed from the access
      // token string and NEVER taken from client input (CRIT-03, LOW-41, FR-8.7).
      const residentSub = tokens.residentSub;
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


