# Implementation Plan: Threshold (threshold-doorbell)

Discrete, ordered, testable tasks. Every task cites the requirements and acceptance tests it satisfies.
Ordering enforces: prove the riskiest capability first, working skeleton early, polish last.

**Revision status.** Resolves all task defects from `SPEC_DESIGN_TASK_ANALYSIS.md`. Previously missing
citations (FR-5.3a, FR-6.4a, FR-6.4b, NFR-1, NFR-5) are now assigned. The former six-subsystem "task 5"
is split into tasks 5 to 9. New workstreams added: capability probe, echo suppression, latency harness,
degradation matrix, threat model, UI-copy lint, model provisioning, documentation.

---

- [x] 1. Project and environment setup
  - Scaffold `app/` (Flutter) and `backend/` (Node 20 + Fastify); wire lint, test runners, lockfile pinning.
  - Define every external dependency as an interface with a fixture implementation (Ring, Transcribe,
    Bedrock, push, store).
  - _Requirements: NFR-8, NFR-9; design §2 version policy_

- [x] 2. **CRITICAL SPIKE: outbound audio and capability probe (before any UI)**
  - [ ] 2.1 Build the single-stack WebView session per ARCH-1: one `RTCPeerConnection` in the WebView,
        audio `sendrecv`, video `recvonly`.
  - [ ] 2.2 Inject synthesized audio: `AudioContext` to `MediaStreamAudioDestinationNode` to
        `sender.replaceTrack`. Verify with a tone, then with `flutter_tts` `synthesizeToFile` output.
  - [ ] 2.3 Implement the capability probe exactly as design §5.1 (near-silent at or below -60 dBFS,
        `getStats()` `packetsSent` delta, 1000 ms timeout) and make the result sticky per session.
  - [ ] 2.4 Build the harness asserting audio energy on the outbound track within 2 s.
  - [ ] 2.5 **Go/no-go gate.** On failure, adopt the native platform-channel alternative; if that also fails,
        Captions-Only (task 17) becomes the shipping scope.
  - _Requirements: FR-4.1, FR-6.1, FR-6.2, FR-6.4a, FR-6.4b, G3; AT-3, AT-5, AT-6_

- [x] 3. Backend: OAuth 2.0 (PKCE) and unified auth recovery
  - `/oauth/start`, `/oauth/callback`, `/oauth/refresh`; state check; server-side secret; refresh-once-on-401.
  - Implement the single unified recovery flow (no second divergent path).
  - _Requirements: FR-1.1 to FR-1.5, FR-1.7, NFR-3; AT-1, AT-12_

- [x] 4. Backend: token storage with KMS encryption
  - `ring_tokens` table, KMS-encrypted access and refresh tokens; Secrets Manager limited to application
    secrets. Assert no Ring token is ever returned to the app or stored on device.
  - _Requirements: FR-1.6, NFR-3; AT-1_

- [x] 5. Backend: webhook receiver (HMAC, idempotent, under 5 s)
  - Constant-time HMAC verify; conditional-put dedupe on `requestId`; acknowledge 200 first, push async.
  - _Requirements: FR-3.1, FR-3.2, NFR-6; AT-2_

- [x] 6. Backend: devices and events routes with pagination and Ring adapter
  - `/devices`, `/events` with `limit`/`cursor` envelope; token-bucket rate limiting with backoff; single
    schema-validating Ring adapter emitting `ring_contract_invalid` on drift.
  - _Requirements: FR-2.1, FR-2.2, FR-2.3, FR-3.5, FR-17.1, FR-17.2, NFR-7; AT-19, AT-23_

- [x] 7. Backend: signaling broker
  - `/signaling` WebSocket; WHEP offer and answer relay; session URL lifecycle; reject a second concurrent
    session with 4409.
  - _Requirements: FR-4.1, FR-4.6, FR-4.7; AT-3, AT-11_

- [x] 8. Backend: ASR relay for Clarity Mode
  - `/asr/stream` WebSocket to Amazon Transcribe streaming with partial-results stabilization; reconnect with
    at most 2 s replay; never switch caption mode mid-session.
  - _Requirements: FR-5.1, G2; AT-4_

- [x] 9. Backend: transcripts, retention, erasure, authorization
  - `/transcripts` create, list (paginated, searchable, date-filtered), delete; `/me/data` erasure;
    90-day TTL; `residentSub` always server-derived, foreign values rejected 403.
  - _Requirements: FR-8.1 to FR-8.7; AT-15, AT-19_

- [x] 10. Backend: Smart Replies (Bedrock, Clarity only)
  - `/replies` returns at most 3 suggestions; 2 s timeout falls back to the fixed safe set; text only;
    never invoked for Privacy-Mode sessions.
  - _Requirements: FR-7.1, FR-7.3, FR-7.4; AT-7_

- [ ] 11. App: push alerts, haptic vocabulary, photosensitivity-safe strobe
  - FCM; exactly three haptic patterns; full-bleed thumbnail; foreground paginated poll fallback; strobe and
    torch capped at 3 flashes per second, off by default.
  - _Requirements: FR-3.3, FR-3.4, FR-3.5, FR-9.1 to FR-9.4; AT-16_

- [x] 12. App: live session (ARCH-1), concurrency, background, auth recovery
  - WebView session; overlays clear of watermark corners; reconnect at most 2; exactly one live session
    (same-device updates context, different-device queues); 5-minute background survival with resume;
    unified auth recovery on session expiry.
  - _Requirements: FR-4.1 to FR-4.8; AT-3, AT-11, AT-12, AT-25_

- [ ] 13. App: Clarity-Mode captions, confidence styling, presence, no-speech
  - Tap inbound audio in the WebView to 16 kHz mono PCM; stream to `/asr/stream`; render partials in
    provisional style; on finalization apply the 0.6 token threshold; presence per FR-5.4; "No speech
    detected" state; turn segmentation; persist unfinalized text as provisional.
  - _Requirements: FR-5.1, FR-5.3, FR-5.3a, FR-5.4, FR-5.5, FR-5.7, G1b, G2; AT-4_

- [x] 14. App: self-transcription suppression (echo gating)
  - Gate the caption pipeline while reply audio plays, hold 300 ms tail, mark the gap in the transcript,
    enable WebRTC echo cancellation on the inbound track.
  - _Requirements: FR-5.6; AT-18_

- [x] 15. App: reply bar and outbound speak
  - At most 3 suggestions plus fixed safe set plus free text; synthesize and inject via task 2; "Speaking at
    your door" state; duplicate-send disabled; append `resident` turn; reply bar disabled when
    `outboundAvailable` is false.
  - _Requirements: FR-6.1, FR-6.3, FR-6.5, FR-7.2, FR-7.5, G3; AT-5, AT-7_

- [ ] 16. App: sticky outbound mode wiring
  - Consume the probe result at session start; keep it sticky; degrade to Captions-Only for the remainder on
    a later injection failure; re-probe next session.
  - _Requirements: FR-6.4, FR-6.4a, FR-6.4b; AT-6_

- [x] 17. App: Captions-Only Mode (receive-only, first-class)
  - Conversation screen without the reply bar; persistent banner; one-tap "Open Ring app" action. No
    visitor-facing prompt (N9). Full regression suite must pass in this mode.
  - _Requirements: FR-12.1 to FR-12.4, N9; AT-6, AT-10_

- [x] 18. App: Privacy Mode (on-device ASR) and model provisioning
  - Opt-in model download outside any session with size disclosure; mode unavailable and labelled until the
    model verifies; on-device inference (native or WASM per ARCH-1); on-device suggestions instead of
    Bedrock; zero audio and zero transcript-text egress.
  - _Requirements: FR-5.2, FR-5.2a, FR-7.1a, FR-10.1, NFR-4; AT-8, AT-21_

- [x] 19. App: visual context processor (privacy-zone aware)
  - On-device object detection on inbound frames; skip masked regions; never transmit frames; feed the
    presence signal used by FR-5.4.
  - _Requirements: FR-11.1, FR-11.2; AT-8_

- [x] 20. App: permissions and consent flows
  - In-context requests for notifications and microphone with rationale; denied and permanently-denied
    handling with an OS-settings deep link; notification denial falls back to poll; camera never requested.
  - _Requirements: FR-13.1 to FR-13.5; AT-13_

- [x] 21. App: recording notice and compliance fallback
  - First-run acknowledgement gate; in-product and privacy-policy disclosure; optional default-off audible
    door notice; when outbound audio is unavailable offer continue-without-notice or disable-transcription
    and honor it for the session.
  - _Requirements: FR-14.1 to FR-14.4; AT-14_

- [x] 22. App: connectivity, offline, and backend-outage behavior
  - Offline state for network features; cached transcripts usable; auto-restore without restart; distinct
    message when connectivity exists but the backend is unreachable.
  - _Requirements: FR-15.1 to FR-15.4; AT-17, AT-20_

- [x] 23. App: language and locale selection
  - Recognition-language selection defaulting to device locale with `en-US` fallback; per-mode supported
    sets documented; unsupported selection reported before session start with an alternative.
  - _Requirements: FR-16.1 to FR-16.3; AT-22_

- [x] 24. Settings and accessibility pass (WCAG 2.2 AA)
  - Mode switch with plain Privacy-Mode explanation; caption size and contrast bounded by a 4.5:1 floor;
    haptic toggles; strobe off by default; language; retention display; "Delete all my data";
    recording-notice text; haptic reference. Automated a11y scan plus manual screen-reader pass per screen;
    zero AA violations gates the build.
  - _Requirements: FR-8.5, FR-8.6, FR-10.1 to FR-10.4, FR-14.1, NFR-2; AT-9_

- [x] 25. Performance: latency harness
  - Automated measurement of G1a, G1b, G2, G3 on both reference devices under reference conditions;
    regression fails CI. Includes the JS-bridge PCM budget from ARCH-1.
  - _Requirements: NFR-1, G1a, G1b, G2, G3_

- [x] 26. Reliability: degradation matrix
  - For each dependency (Bedrock, Transcribe, push, visual processor, backend) implement and test the defined
    degraded behavior; assert no session crashes and no dependency failure is silent.
  - _Requirements: NFR-5, FR-15.4; AT-20_

- [x] 27. Security: threat model and authorization tests
  - Written threat model; authorization suite proving `residentSub` is always server-derived and foreign
    values are rejected; assert no Ring token on device; assert log redaction.
  - _Requirements: FR-1.6, FR-1.7, FR-8.7, NFR-3; AT-19_

- [x] 28. Observability
  - Redacting structured logs with `requestId` correlation; metrics for latency, probe success,
    Captions-Only share, fallback rates, schema-validation failures; in-app debug overlay; prod alarms.
  - _Requirements: NFR-3; design §10_

- [x] 29. CI/CD, UI-copy lint, environments
  - Gates on pull requests: lint, unit, contract, a11y, latency, and the **em-dash and en-dash UI-string
    lint**; local, staging, and demo configurations with fixtures and cached golden responses; CI config never
    pushed directly to `main`; deploy on merge after gates.
  - _Requirements: NFR-10; design §11; steering/structure.md UI copy rules_

- [x] 30. Documentation
  - README as a case study; privacy policy covering FR-14.2; operational runbook (token rotation, KMS key,
    alarm response); haptic-pattern reference; friction log maintained continuously for the submission.
  - _Requirements: FR-14.2; project submission needs_

- [x] 31. Open-source extraction (mini-challenge)
  - Extract the caption and reply bridge as MIT `flutter_ring_captions`; open a focused pull request to
    `AmazonAppDev/ring-api-helloworld` adding an accessibility-oriented video processor.
  - _Requirements: project goals (Open Source mini-challenge)_
