// Server-side OAuth transaction store (HIGH-17). Holds the PKCE codeVerifier
// keyed by the CSRF nonce between /oauth/start and /oauth/callback so the
// verifier never travels in the front channel. Entries are single-use and
// short-lived: take() removes the entry, so a replayed state cannot be redeemed
// twice (HIGH-16). The real horizontally-scaled deployment backs this with a
// short-TTL datastore (for example DynamoDB with a TTL); the fixture is a
// per-process map that evicts on expiry.

export interface OAuthTxnStorePort {
  /** Store the PKCE verifier for a nonce with a time-to-live. */
  put(nonce: string, codeVerifier: string, ttlMs: number): Promise<void>;
  /**
   * Atomically read and remove the verifier for a nonce. Returns null when the
   * nonce is unknown, already consumed, or expired. Single-use: a second call
   * for the same nonce returns null (replay rejection, HIGH-16).
   */
  take(nonce: string): Promise<string | null>;
}
