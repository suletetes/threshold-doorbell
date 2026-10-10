// Session invalidation (HIGH-23). Erasure must invalidate a resident's active
// session so a stateless bearer cannot keep reading data for up to 30 minutes
// after DELETE /me/data. We record a per-resident cutoff: any session issued at
// or before the cutoff is denied. The guard checks this on every authenticated
// request. The real deployment persists the cutoff (a session version) in the
// datastore; the fixture is a per-process map.

export interface SessionInvalidationPort {
  /** Deny every session for a resident issued at or before `cutoffMs`. */
  revokeSessionsIssuedBefore(residentSub: string, cutoffMs: number): Promise<void>;
  /** True when a session for `residentSub` issued at `iatMs` is denied. */
  isRevoked(residentSub: string, iatMs: number): Promise<boolean>;
}
