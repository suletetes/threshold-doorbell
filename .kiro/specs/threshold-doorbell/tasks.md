# Implementation Plan — Threshold (threshold-doorbell)

Discrete, ordered, testable coding tasks. Each references the requirements it satisfies. Checkboxes track
progress. The order enforces the champion rule: prove the riskiest thing first, ugly skeleton by the 25%
mark, polish last.

- [ ] 1. Project & environment setup
  - Scaffold `app/` (Flutter) and `backend/` (Node 20 + Fastify) workspaces; wire lint + test runners.
  - Configure secure token storage stubs and the fixtures for Ring + AWS behind interfaces.
  - _Requirements: NFR-8, NFR-9_

- [ ] 2. **CRITICAL SPIKE — outbound audio (do before any UI)**
  - [ ] 2.1 Stand up a WebView audio pipeline: browser WebRTC + `AudioContext` → `MediaStreamTrack`.
  - [ ] 2.2 Open a Ring WebRTC session (audio `sendrecv`, video `recvonly`) and inject a synthesized tone,
        then `flutter_tts` `synthesizeToFile` output, into the outbound track.
  - [ ] 2.3 Build the automated harness (AT-5): assert measurable audio energy on the outbound track ≤ 2 s.
  - [ ] 2.4 **Go/no-go gate.** If unavailable, activate the Captions-Only scope decision (task 12).
  - _Requirements: FR-6.1, FR-6.2, FR-6.3, G3; AT-5_

- [ ] 3. Backend: OAuth 2.0 (PKCE) linking + refresh
  - `/oauth/start`, `/oauth/callback`, `/oauth/refresh`; state check; server-side secret; secure token store.
  - Refresh-once-on-401 wrapper around Ring calls; preserve state on refresh failure.
  - _Requirements: FR-1.1–1.6, NFR-3; AT-1_

- [ ] 4. Backend: webhook receiver (idempotent, HMAC, ≤5 s)
  - Constant-time HMAC verify; conditional-put dedupe by `requestId`; async push enqueue; 200 within 5 s.
  - _Requirements: FR-3.1, FR-3.2, NFR-6; AT-2_

- [ ] 5. Backend: devices, events, transcripts, signaling, ASR, replies routes
  - Implement all routes in design §4 with Fastify JSON-schema validation and the error envelope.
  - Ring rate limiting (token bucket + backoff); DynamoDB (prod) / fixture (local) store.
  - _Requirements: FR-2, FR-8, NFR-6, NFR-7_

- [ ] 6. App: push alerts + haptic vocabulary + photosensitivity-safe strobe
  - FCM integration; event→haptic mapping (≥3 patterns); full-bleed thumbnail; foreground poll fallback;
    strobe/torch alert capped at ≤3 flashes/second, off by default.
  - _Requirements: FR-3.3–3.5, FR-9.1–9.4; AT-16_

- [ ] 7. App: live session (WebRTC inbound) + concurrency + session-expiry
  - `flutter_webrtc` session; SDP `sendrecv`/`recvonly`; route inbound audio to ASR; overlay out of
    watermark corners; reconnect ≤2; close on background >30 s. Enforce single live session: same-device
    event updates context, different-device event queues. Non-destructive re-auth on backend-session expiry.
  - _Requirements: FR-4.1–4.8; AT-3, AT-11, AT-12_

- [ ] 8. App+backend: Clarity-Mode captions (Amazon Transcribe streaming)
  - Stream inbound PCM → Transcribe WS; render partials; confidence styling (<0.6 de-emphasized); turn
    segmentation; "No speech detected" state.
  - _Requirements: FR-5.1, FR-5.3, FR-5.4, FR-5.5, G2; AT-4_

- [ ] 9. App: reply bar + outbound speak (built on the proven spike)
  - ≤3 Smart Replies + fixed safe set + free text; synthesize → inject via task-2 pipeline; "Speaking at
    your door…"; disable duplicate send; append `resident` turn.
  - _Requirements: FR-6.1, FR-6.3, FR-6.5, FR-7.2, G3_

- [ ] 10. Backend: Smart Replies (Bedrock) with hard fallback
  - `/replies` returns ≤3 suggestions from Bedrock; 2 s timeout → fixed safe set; text-only to Bedrock.
  - _Requirements: FR-7.1, FR-7.3, FR-7.4; AT-7_

- [ ] 11. App+backend: transcript persistence, history, retention & erasure
  - Persist text-only turns on session end; searchable + date filter; delete with confirm; never store
    audio/video. 90-day TTL auto-delete; "Delete all my data" (erase transcripts + revoke token).
  - _Requirements: FR-8.1–8.6, N6; AT-8, AT-15_

- [ ] 12. App: Captions-Only degrade mode (fallback, first-class)
  - Visitor-facing on-screen/QR prompt; full feature set minus spoken reply; explicit notice; not an error.
  - Make the full test suite pass in this mode.
  - _Requirements: FR-6.4, FR-12.1, FR-12.2; AT-6, AT-10_

- [ ] 13. App: Privacy Mode (on-device ASR) — stretch
  - whisper.cpp via `whisper_ggml`/FFI + VAD; zero audio egress; toggle applies next session with indicator.
  - Network-capture test asserts zero egress.
  - _Requirements: FR-5.2, FR-10.1, NFR-4; AT-8_

- [ ] 14. App: visual context processor (privacy-zone aware)
  - `google_mlkit_object_detection` on inbound frames on-device; skip masked regions; person/package cues.
  - _Requirements: FR-11.1_

- [ ] 15. App: permissions & consent flows
  - `permission_handler`; in-context requests for notifications/mic/camera/vibration with rationale;
    denied + permanently-denied handling with OS-settings deep link; notification-denied → poll fallback.
  - _Requirements: FR-13.1–13.5; AT-13_

- [ ] 16. App: visitor recording notice & optional door notice
  - First-run acknowledgement gate; in-product + privacy-policy disclosure; optional default-off audible
    door notice at session start via the outbound-audio path.
  - _Requirements: FR-14.1–14.4; AT-14_

- [ ] 17. App: connectivity & offline behavior
  - `connectivity_plus`; offline state for network features; cached transcripts usable offline; auto-restore
    online without restart.
  - _Requirements: FR-15.1–15.3; AT-17_

- [ ] 18. Settings + accessibility pass (WCAG 2.2 AA)
  - Privacy/Clarity toggle, caption size/contrast live preview, haptic toggles, strobe/torch (off by
    default), retention display, "Delete all my data", recording-notice text; OS text-scale + reduce-motion;
    per-screen automated a11y scan + manual screen-reader pass; zero AA violations gate. No em-dash in any
    UI string.
  - _Requirements: FR-8.5, FR-8.6, FR-10.1–10.4, FR-14, NFR-2; AT-9_

- [ ] 19. Observability
  - Structured redacting logs; latency/success/fallback metrics; in-app debug overlay for demo; prod alarms.
  - _Requirements: NFR-3 (no PII in logs), design §10_

- [ ] 20. CI/CD + environments
  - Lint/unit/contract/a11y gates on PR; local/staging/demo configs; fixtures + cached golden responses for
    demo safety; deploy on merge to `main` after gates.
  - _Requirements: design §11_

- [ ] 21. Open-source extraction (mini-challenge)
  - Extract the caption/reply bridge as MIT `flutter_ring_captions`; open a focused PR to
    `AmazonAppDev/ring-api-helloworld` (accessibility-oriented video processor).
  - _Requirements: project goals (Open Source mini-challenge)_
