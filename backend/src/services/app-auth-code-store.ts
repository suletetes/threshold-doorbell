// Server-side one-time app authorization code store (HIGH-18). After a
// successful OAuth callback the backend mints a short-lived, single-use code and
// redirects to the native app deep link carrying it. The app then exchanges
// that code over HTTPS for its session credential, so the session reaches the
// native client instead of being stranded in a browser cookie.
//
// The code is opaque and high-entropy; take() removes it so it cannot be
// redeemed twice. The real horizontally-scaled deployment backs this with a
// short-TTL datastore; the fixture is a per-process map.

export interface AppAuthCodeStorePort {
  /** Store the residentSub a one-time code resolves to, with a time-to-live. */
  put(code: string, residentSub: string, ttlMs: number): Promise<void>;
  /**
   * Atomically read and remove the residentSub for a code. Returns null when
   * the code is unknown, already consumed, or expired (single-use).
   */
  take(code: string): Promise<string | null>;
}
