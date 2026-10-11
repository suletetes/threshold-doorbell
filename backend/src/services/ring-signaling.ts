// Ring signaling port (Task 7, FR-4.1, FR-4.3, FR-4.6, FR-4.7). Isolates the
// WHEP offer/answer exchange with Ring behind a single interface so the broker
// route never speaks HTTP to Ring directly (ports and adapters, structure.md).
//
// The real adapter performs the Ring WHEP POST (SDP offer up, SDP answer down)
// and holds the returned Ring session URL for later release. The fixture returns
// a canned, schema-valid SDP answer and a session URL, and records URL releases
// so the session lifecycle is unit-testable without a live Ring device.

/** A live Ring session handle returned by a successful WHEP negotiation. */
export interface RingSessionHandle {
  /** SDP answer to relay back to the WebView peer (design.md §4). */
  sdpAnswer: string;
  /**
   * The Ring session URL. It is used to release the session on end
   * (FR-4.3) and is never exposed to the device beyond what the app needs to
   * drive the WebView peer connection.
   */
  sessionUrl: string;
}

export interface StartSessionInput {
  /** The WebRTC SDP offer produced by the WebView peer (WHEP). */
  sdpOffer: string;
  /** The Ring device the session targets. */
  deviceId: string;
  /**
   * The resident's Ring access token. A real adapter needs app-level Ring
   * credentials to open a session; passing it here means the broker always
   * authorizes through the resident's own grant (HIGH-20) rather than opening a
   * session for an arbitrary device.
   */
  accessToken: string;
}

export interface RingSignalingPort {
  /**
   * Relay a WHEP SDP offer to Ring and return the SDP answer plus the Ring
   * session URL. Implementations MUST validate the Ring response and throw on
   * an unexpected payload so the broker degrades rather than crashes (FR-17).
   */
  startSession(input: StartSessionInput): Promise<RingSessionHandle>;

  /**
   * Release a Ring session URL when the session ends (FR-4.3). Idempotent: a
   * repeated release of the same URL is a no-op so a close-plus-timeout race
   * cannot throw.
   */
  releaseSession(sessionUrl: string): Promise<void>;
}
