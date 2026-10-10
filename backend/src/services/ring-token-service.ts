// RingTokenService: the single place that stores, encrypts, refreshes, and vends
// Ring tokens (FR-1.2, FR-1.4, FR-1.6). Tokens are KMS-encrypted at rest (via the
// CryptoPort) and NEVER returned to the app or written to logs. This service also
// implements refresh-once-on-401-and-retry (FR-1.4) and, on refresh failure,
// surfaces refresh_failed so the caller runs the single unified recovery flow
// (FR-1.5). There is exactly one recovery path: any auth failure -> refresh_failed.

import { errors } from '../domain/errors.js';
import type { RingTokenRecord } from '../domain/types.js';
import type { CryptoPort } from './crypto.js';
import type { OAuthTokens, RingPort } from './ring.js';
import type { TokenStorePort } from './stores.js';

const REFRESH_SKEW_MS = 120 * 1000; // refresh within 120 s of expiry (FR-1.4)

export class RingTokenService {
  // MED-31: single-flight refresh per resident. Concurrent callers that both
  // need a refresh share one in-flight refresh instead of each spending the
  // refresh token; a refresh-token rotation then cannot log the other caller
  // out by invalidating the token it was about to use.
  private readonly refreshInFlight = new Map<string, Promise<string>>();

  constructor(
    private readonly ring: RingPort,
    private readonly store: TokenStorePort,
    private readonly crypto: CryptoPort,
  ) {}

  /** Persist freshly obtained tokens for a resident, encrypted at rest. */
  async persist(residentSub: string, tokens: OAuthTokens): Promise<void> {
    const record: RingTokenRecord = {
      residentSub,
      accessTokenEnc: await this.crypto.encrypt(tokens.accessToken),
      refreshTokenEnc: await this.crypto.encrypt(tokens.refreshToken),
      expiresAt: tokens.expiresAt,
    };
    await this.store.put(record);
  }

  /** Remove a resident's stored tokens (erasure / revoke, FR-8.6). */
  async revoke(residentSub: string): Promise<void> {
    await this.store.delete(residentSub);
  }

  /**
   * Return a valid Ring access token for a resident, refreshing proactively when
   * within the expiry skew (FR-1.4). Never returns the token to the app; callers
   * use it only for server-side Ring calls. Throws refresh_failed on any refresh
   * failure so the unified recovery flow runs (FR-1.5).
   */
  async getAccessToken(residentSub: string, now = Date.now()): Promise<string> {
    const record = await this.store.get(residentSub);
    if (!record) throw errors.refreshFailed();

    const expiresMs = Date.parse(record.expiresAt);
    const nearExpiry = Number.isFinite(expiresMs) && expiresMs - now <= REFRESH_SKEW_MS;
    if (!nearExpiry) {
      // MED-31: a decrypt failure here must surface as refresh_failed (the
      // unified recovery signal), not as an unlogged 500.
      try {
        return await this.crypto.decrypt(record.accessTokenEnc);
      } catch {
        throw errors.refreshFailed();
      }
    }
    // Proactive refresh.
    return this.refreshAndStore(residentSub, record);
  }

  /**
   * Run a Ring call that needs an access token, refreshing once and retrying
   * exactly once on a 401 (FR-1.4). Any refresh failure becomes refresh_failed.
   */
  async withAccessToken<T>(
    residentSub: string,
    call: (accessToken: string) => Promise<T>,
    now = Date.now(),
  ): Promise<T> {
    const token = await this.getAccessToken(residentSub, now);
    try {
      return await call(token);
    } catch (err) {
      if (!isUnauthorized(err)) throw err;
      // 401: refresh once and retry exactly once.
      const record = await this.store.get(residentSub);
      if (!record) throw errors.refreshFailed();
      const refreshed = await this.refreshAndStore(residentSub, record);
      return call(refreshed);
    }
  }

  private async refreshAndStore(
    residentSub: string,
    record: RingTokenRecord,
  ): Promise<string> {
    // MED-31: coalesce concurrent refreshes for the same resident so the
    // refresh token is spent at most once per burst.
    const existing = this.refreshInFlight.get(residentSub);
    if (existing) return existing;
    const run = this.doRefresh(residentSub, record).finally(() => {
      this.refreshInFlight.delete(residentSub);
    });
    this.refreshInFlight.set(residentSub, run);
    return run;
  }

  private async doRefresh(residentSub: string, record: RingTokenRecord): Promise<string> {
    let refreshToken: string;
    try {
      refreshToken = await this.crypto.decrypt(record.refreshTokenEnc);
    } catch {
      throw errors.refreshFailed();
    }
    let tokens: OAuthTokens;
    try {
      tokens = await this.ring.refresh(refreshToken);
    } catch {
      throw errors.refreshFailed();
    }
    await this.persist(residentSub, tokens);
    return tokens.accessToken;
  }
}

/** A Ring call is "unauthorized" when it signals a 401 (unauthorized code). */
function isUnauthorized(err: unknown): boolean {
  return (
    typeof err === 'object' &&
    err !== null &&
    'code' in err &&
    (err as { code?: unknown }).code === 'unauthorized'
  );
}
