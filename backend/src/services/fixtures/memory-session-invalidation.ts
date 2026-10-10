// In-memory session invalidation deny-list (design.md §11 "local", HIGH-23).
// Per-process map of residentSub -> cutoff timestamp. A session is denied when
// its issued-at is at or before the cutoff.

import type { SessionInvalidationPort } from '../session-invalidation.js';

export class MemorySessionInvalidation implements SessionInvalidationPort {
  private readonly cutoffByResident = new Map<string, number>();

  async revokeSessionsIssuedBefore(residentSub: string, cutoffMs: number): Promise<void> {
    const existing = this.cutoffByResident.get(residentSub);
    // Keep the latest cutoff so a repeated erasure never narrows the window.
    if (existing === undefined || cutoffMs > existing) {
      this.cutoffByResident.set(residentSub, cutoffMs);
    }
  }

  async isRevoked(residentSub: string, iatMs: number): Promise<boolean> {
    const cutoff = this.cutoffByResident.get(residentSub);
    if (cutoff === undefined) return false;
    return iatMs <= cutoff;
  }
}
