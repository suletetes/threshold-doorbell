// Signaling broker service (Task 7, FR-4.1, FR-4.6, FR-4.7; AT-3, AT-11).
//
// Enforces the invariant that exactly one live session exists per resident at a
// time (FR-4.7). A second concurrent attempt is rejected so the route can close
// it with WS code 4409. A same-device event does not open a second session
// (FR-4.6); that context update is handled app-side, and this broker simply
// refuses any duplicate open. On end (explicit close or timeout) the Ring
// session URL is released (FR-4.3).
//
// DEFERRED (cross-instance limitation): the `active` registry below is a
// per-PROCESS in-memory map, so the single-session-per-resident invariant
// (FR-4.7) holds within ONE instance only. Across a multi-process / multi-pod
// deployment a resident could hold one live session per instance, which breaks
// FR-4.7 globally. This is correct for the single-process fixture but is NOT a
// cross-instance guarantee. The real horizontally-scaled deployment MUST record
// the active session in a shared datastore keyed by residentSub (e.g. a
// conditional-write "claim" row / distributed lock with the TTL below as the
// lease), so a second concurrent open is rejected regardless of which instance
// serves it. Tracked in
// .agents/tasks/task-audit-remediation/features/FEAT-004.json (deferred).
// This fixture-backed service proves the lifecycle and rejection rules.

import type { RingSessionHandle, RingSignalingPort } from './ring-signaling.js';

/** Default maximum lifetime of a signaling slot before it is force-released. */
export const MAX_SESSION_MS = 10 * 60 * 1000; // 10 minutes (FR-4.3 safety cap)

/** A tracked active session for a resident. */
interface ActiveSession {
  residentSub: string;
  deviceId: string;
  sessionUrl: string;
  /** Timer that force-releases the slot if the session outlives its TTL. */
  ttl: ReturnType<typeof setTimeout> | null;
}

/** Raised when a resident already holds a live session (FR-4.7 -> WS 4409). */
export class SessionAlreadyActiveError extends Error {
  constructor() {
    super('A live session is already active for this resident.');
    this.name = 'SessionAlreadyActiveError';
  }
}

/** Raised when a resident requests a session for a device they do not own (HIGH-20). */
export class DeviceNotAuthorizedError extends Error {
  constructor() {
    super('That device is not registered to this resident.');
    this.name = 'DeviceNotAuthorizedError';
  }
}

/**
 * Collaborators the broker needs to authorize a session: a per-resident access
 * token source (so the Ring relay uses the resident's own grant) and an
 * ownership check for the target device (HIGH-20).
 */
export interface SignalingAuthz {
  /** Run a function with the resident's Ring access token (refresh-once applies). */
  withAccessToken<T>(residentSub: string, call: (accessToken: string) => Promise<T>): Promise<T>;
  /** True when `deviceId` belongs to `residentSub`. */
  ownsDevice(residentSub: string, deviceId: string): Promise<boolean>;
}

export class SignalingService {
  private readonly active = new Map<string, ActiveSession>();

  constructor(
    private readonly signaling: RingSignalingPort,
    private readonly authz: SignalingAuthz,
    private readonly maxSessionMs: number = MAX_SESSION_MS,
  ) {}

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
    // HIGH-20: a resident may only open a session for a device they own. The
    // ownership check runs BEFORE the slot is reserved so an unauthorized
    // request neither reserves nor touches the incumbent.
    if (!(await this.authz.ownsDevice(residentSub, deviceId))) {
      throw new DeviceNotAuthorizedError();
    }
    // Reserve the slot before the async relay so two racing opens cannot both
    // pass the check. A relay failure below frees it again. A TTL timer force
    // releases the slot if the session outlives its maximum duration, so a
    // leaked slot can never lock a resident out indefinitely (HIGH-19).
    const ttl = setTimeout(() => {
      void this.close(residentSub);
    }, this.maxSessionMs);
    // Do not keep the event loop alive solely for this timer.
    if (typeof ttl.unref === 'function') ttl.unref();
    this.active.set(residentSub, { residentSub, deviceId, sessionUrl: '', ttl });
    try {
      // HIGH-20: open through the resident's own Ring grant; the access token is
      // threaded into the relay call rather than opening for an arbitrary device.
      const handle = await this.authz.withAccessToken(residentSub, (accessToken) =>
        this.signaling.startSession({ sdpOffer, deviceId, accessToken }),
      );
      const current = this.active.get(residentSub);
      // If the slot was released while the relay was in flight (close during
      // handshake), release the freshly issued Ring URL and do not re-reserve.
      if (!current || current.ttl !== ttl) {
        await this.signaling.releaseSession(handle.sessionUrl);
        return handle;
      }
      this.active.set(residentSub, { residentSub, deviceId, sessionUrl: handle.sessionUrl, ttl });
      return handle;
    } catch (err) {
      this.clearSlot(residentSub, ttl);
      throw err;
    }
  }

  private clearSlot(residentSub: string, ttl: ActiveSession['ttl']): void {
    if (ttl) clearTimeout(ttl);
    const current = this.active.get(residentSub);
    if (current && current.ttl === ttl) {
      this.active.delete(residentSub);
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
    if (session.ttl) clearTimeout(session.ttl);
    if (session.sessionUrl !== '') {
      await this.signaling.releaseSession(session.sessionUrl);
    }
  }
}
