// In-memory one-time app authorization code store (design.md §11 "local",
// HIGH-18). Per-process map of code -> { residentSub, expiresAt }. take() is
// single-use and expiry-aware so a replayed or stale code cannot be redeemed.

import type { AppAuthCodeStorePort } from '../app-auth-code-store.js';

interface Entry {
  residentSub: string;
  expiresAt: number;
}

export class MemoryAppAuthCodeStore implements AppAuthCodeStorePort {
  private readonly byCode = new Map<string, Entry>();

  constructor(private readonly now: () => number = () => Date.now()) {}

  async put(code: string, residentSub: string, ttlMs: number): Promise<void> {
    this.byCode.set(code, { residentSub, expiresAt: this.now() + ttlMs });
  }

  async take(code: string): Promise<string | null> {
    const entry = this.byCode.get(code);
    // Single-use: remove on read so a replay finds nothing.
    this.byCode.delete(code);
    if (!entry) return null;
    if (this.now() >= entry.expiresAt) return null;
    return entry.residentSub;
  }
}
