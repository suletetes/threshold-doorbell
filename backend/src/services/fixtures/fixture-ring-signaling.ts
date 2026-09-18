// Fixture Ring signaling adapter (Task 7, FR-4.1; AT-3, AT-11). Returns a canned
// SDP answer that satisfies the AT-3 session shape (audio sendrecv, video
// recvonly) and a unique session URL, and records every released URL so the
// session-lifecycle and URL-release rules are testable without a live Ring
// device. Failure injection lets tests drive the connect-failure path (FR-4.4).

import type {
  RingSessionHandle,
  RingSignalingPort,
  StartSessionInput,
} from '../ring-signaling.js';

/**
 * A canned SDP answer whose media lines match the AT-3 session shape: audio is
 * negotiated `sendrecv` (two-way) and video is `recvonly` (inbound only). The
 * broker relays this verbatim to the WebView peer.
 */
export const FIXTURE_SDP_ANSWER = [
  'v=0',
  'o=- 4611731400430051336 2 IN IP4 127.0.0.1',
  's=-',
  't=0 0',
  'm=audio 9 UDP/TLS/RTP/SAVPF 111',
  'a=sendrecv',
  'm=video 9 UDP/TLS/RTP/SAVPF 96',
  'a=recvonly',
].join('\r\n');

export class FixtureRingSignaling implements RingSignalingPort {
  private counter = 0;
  private mode: 'ok' | 'error' = 'ok';
  private readonly released = new Set<string>();
  private readonly issued = new Set<string>();

  /** Simulate a Ring connect failure so the broker's retry/close path is tested. */
  setError(): void {
    this.mode = 'error';
  }

  /** Restore normal canned responses. */
  setOk(): void {
    this.mode = 'ok';
  }

  /** URLs that have been released, for lifecycle assertions. */
  releasedUrls(): readonly string[] {
    return [...this.released];
  }

  /** True when a specific session URL was released. */
  wasReleased(sessionUrl: string): boolean {
    return this.released.has(sessionUrl);
  }

  /** URLs that were issued by startSession, for lifecycle assertions. */
  issuedUrls(): readonly string[] {
    return [...this.issued];
  }

  async startSession(input: StartSessionInput): Promise<RingSessionHandle> {
    if (this.mode === 'error') {
      throw new Error('ring signaling unavailable');
    }
    if (typeof input.sdpOffer !== 'string' || input.sdpOffer === '') {
      // A missing offer is a contract violation the broker surfaces as an error.
      throw new Error('empty sdp offer');
    }
    this.counter += 1;
    const sessionUrl = `https://fixture.ring.local/session/${input.deviceId}/${this.counter}`;
    this.issued.add(sessionUrl);
    return { sdpAnswer: FIXTURE_SDP_ANSWER, sessionUrl };
  }

  async releaseSession(sessionUrl: string): Promise<void> {
    // Idempotent: releasing an unknown or already-released URL is a no-op.
    this.released.add(sessionUrl);
  }
}
