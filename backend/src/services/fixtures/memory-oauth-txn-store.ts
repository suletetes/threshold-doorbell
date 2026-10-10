// In-memory OAuth transaction store (design.md §11 "local", HIGH-17).
// Per-process map of nonce -> { codeVerifier, expiresAt }. take() is single-use
// and expiry-aware so a replayed or stale state cannot be redeemed.

import type { OAuthTxnStorePort } from '../oauth-txn-store.js';

interface Entry {
  codeVerifier: string;
  expiresAt: number;
}

export class MemoryOAuthTxnStore implements OAuthTxnStorePort {
  private readonly byNonce = new Map<string, Entry>();

  constructor(private readonly now: () => number = () => Date.now()) {}

  async put(nonce: string, codeVerifier: string, ttlMs: number): Promise<void> {
    this.byNonce.set(nonce, { codeVerifier, expiresAt: this.now() + ttlMs });
  }

  async take(nonce: string): Promise<string | null> {
    const entry = this.byNonce.get(nonce);
    // Single-use: remove on read so a replay finds nothing.
    this.byNonce.delete(nonce);
    if (!entry) return null;
    if (this.now() >= entry.expiresAt) return null;
    return entry.codeVerifier;
  }
}
