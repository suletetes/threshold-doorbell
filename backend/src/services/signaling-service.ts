// Signaling broker service (Task 7, FR-4.1, FR-4.6, FR-4.7; AT-3, AT-11).
//
// Enforces the invariant that exactly one live session exists per resident at a
// time (FR-4.7). A second concurrent attempt is rejected so the route can close
// it with WS code 4409. A same-device event does not open a second session
// (FR-4.6); that context update is handled app-side, and this broker simply
// refuses any duplicate open. On end (explicit close or timeout) the Ring
// session URL is released (FR-4.3).
//
// The registry is per-instance in-memory. The real horizontally-scaled
// deployment records the active session in the datastore keyed by residentSub;
// this fixture-backed service proves the lifecycle and rejection rules.

import type { RingSessionHandle, RingSignalingPort } from './ring-signaling.js';

/** A tracked active session for a resident. */
interface ActiveSession {
  residentSub: string;
  deviceId: string;
  sessionUrl: string;
}

/** Raised when a resident already holds a live session (FR-4.7 -> WS 4409). */
export class SessionAlreadyActiveError extends Error {
  constructor() {
    super('A live session is already active for this resident.');
    this.name = 'SessionAlreadyActiveError';
  }
}

export class SignalingService {
  private readonly active = new Map<string, ActiveSession>();

  constructor(private readonly signaling: RingSignalingPort) {}

  /** True when the resident currently holds a live session. */
  hasActiveSession(residentSub: string): boolean {
    return this.active.has(residentSub);
  }

  /** The active session URL for a resident, or null. */
  activeSessionUrl(residentSub: string): string | null {
    return this.active.get(residentSub)?.sessionUrl ?? null;
  }

  /**
   * Open a session: reserve the single slot for the resident, relay the WHEP
   * offer to Ring, and return the answer plus session URL. Throws
   * SessionAlreadyActiveError if the resident already has a live session
   * (FR-4.7). If the Ring relay fails, the slot is freed so a retry can proceed
   * and the caller surfaces a connect error (FR-4.4).
   */
  async open(
    residentSub: string,
    deviceId: string,
    sdpOffer: string,
  ): Promise<RingSessionHandle> {
    if (this.active.has(residentSub)) {
      throw new SessionAlreadyActiveError();
    }
    // Reserve the slot before the async relay so two racing opens cannot both
    // pass the check. A relay failure below frees it again.
    this.active.set(residentSub, { residentSub, deviceId, sessionUrl: '' });
    try {
      const handle = await this.signaling.startSession({ sdpOffer, deviceId });
      this.active.set(residentSub, { residentSub, deviceId, sessionUrl: handle.sessionUrl });
      return handle;
    } catch (err) {
      this.active.delete(residentSub);
      throw err;
    }
  }

  /**
   * Close a resident's session and release its Ring session URL (FR-4.3).
   * Idempotent: closing when there is no active session is a no-op, so a
   * client disconnect plus a timeout cannot double-release or throw.
   */
  async close(residentSub: string): Promise<void> {
    const session = this.active.get(residentSub);
    if (!session) return;
    this.active.delete(residentSub);
    if (session.sessionUrl !== '') {
      await this.signaling.releaseSession(session.sessionUrl);
    }
  }
}
