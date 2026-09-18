# Requirements — Threshold (threshold-doorbell)

Two-way captioned Ring doorbell for deaf and hard-of-hearing residents.
Amazon Developer Hackathon 2026 · Ring track · Flutter (iOS + Android) + backend.

Acceptance criteria use EARS syntax (WHEN/IF/WHILE … THE SYSTEM SHALL …). Every requirement is atomic and
testable. There are no open questions; all ambiguities are resolved in this document.

---

## 1. Overview & goals

Threshold turns a Ring video doorbell into a two-way, text-based conversation device for people who cannot
hear. When a visitor speaks, the resident sees live captions on their phone; when the resident taps or types
a reply, a synthesized voice is played out of the doorbell so the visitor hears it. The product's defining
capability is the **outbound reply through the doorbell**, built on Ring's bidirectional (`sendrecv`)
WebRTC audio channel.

**Goals (measurable):**
- G1. From doorbell event to first on-screen caption in ≤ 3.0 s (Clarity Mode, good network).
- G2. Caption partial-result latency ≤ 1.0 s after speech onset (Clarity Mode).
- G3. Resident reply audible at the doorbell in ≤ 2.0 s after tap (measured tap→audio-start).
- G4. Fully operable with device sound off and a screen reader on; WCAG 2.2 AA conformance on all screens.
- G5. Zero doorstep audio leaves the device in Privacy Mode (verifiable: no network egress during capture).

**Primary success definition:** a resident completes a full two-way exchange (visitor speaks → caption →
resident replies → reply audible at door → visitor responds → caption) without hearing, in a live demo,
without falling back to a mock.

---

## 2. Non-goals / out of scope

- N1. No open-ended conversational AI / chatbot persona. AI is limited to: speech→text, text→speech, and a
  bounded set of ≤ 3 suggested replies.
- N2. No live language translation (explicitly deferred).
- N3. No sign-language gesture recognition (deferred).
- N4. No Fire TV / Alexa companion surface (deferred).
- N5. No user-account system of our own beyond Ring OAuth identity; no social features; no multi-tenant
  admin console.
- N6. No storage or replay of visitor **audio or video**. Only derived **text** transcripts are persisted.
- N7. No support for non-Ring doorbells in this version.
- N8. Not a certified Ring App Store production release within the hackathon window; target is a
  demo-ready, staging-validated build.

---

## 3. Personas & roles

| Role | Description | Capabilities |
|---|---|---|
| **Resident (primary user)** | The deaf/HoH Ring owner. Persona: Priya, 34, profoundly deaf. | Receive alerts, open live session, read captions, send replies, view/search transcript history, configure settings. |
| **Caretaker resident** | Older HoH user. Persona: Bernard, 78. | Same as Resident; relies more on scripted replies and larger text. |
| **Visitor** | Person at the door. Not an app user. | Heard (audio captured for captioning) and spoken to (reply audio played at door). Has no account and no UI. |
| **System/backend** | Server components. | Receive Ring webhooks, exchange/refresh OAuth tokens, broker WebRTC signaling, run Clarity-Mode ASR, generate Smart Replies, persist transcripts. |

There is exactly one authenticated human role (Resident). The Visitor is a non-authenticated external actor.

---

## 4. Functional requirements

### FR-1 — Ring account linking (OAuth 2.0)
- 1.1 WHEN the resident starts account linking, THE SYSTEM SHALL initiate the Ring OAuth 2.0 authorization-
  code flow with PKCE and a cryptographically random `state`.
- 1.2 WHEN Ring redirects back with an authorization code, THE SYSTEM SHALL exchange it for access and
  refresh tokens server-side and SHALL NOT expose the client secret to the mobile app.
- 1.3 IF the returned `state` does not match the value the backend issued, THE SYSTEM SHALL reject the
  callback and SHALL display "Sign-in could not be verified. Please try again."
- 1.4 WHEN an access token is within 120 s of expiry OR a Ring API call returns 401, THE SYSTEM SHALL
  refresh the token using the refresh token before retrying the original call exactly once.
- 1.5 IF token refresh fails, THE SYSTEM SHALL preserve any in-progress conversation state locally and
  SHALL prompt the resident to re-link, without losing the current transcript.
- 1.6 THE SYSTEM SHALL store tokens only in the backend secret store and in the device secure enclave
  (Keychain/Keystore), never in plaintext, logs, or shared preferences.

### FR-2 — Device discovery
- 2.1 WHEN linking succeeds, THE SYSTEM SHALL fetch the resident's authorized Ring devices and their
  capabilities and SHALL cache them for ≤ 24 h.
- 2.2 IF the account has zero compatible devices, THE SYSTEM SHALL display an explicit empty state and, in
  demo builds, SHALL offer to load a deterministic fixture device.
- 2.3 THE SYSTEM SHALL respect the Ring API rate limit of 100 requests/second using client-side token-bucket
  throttling and exponential backoff with jitter on 429/5xx.

### FR-3 — Event ingestion & alerting
- 3.1 WHEN Ring POSTs a webhook, THE SYSTEM (backend) SHALL validate the HMAC signature and SHALL return
  HTTP 200 within 5 s.
- 3.2 THE SYSTEM SHALL deduplicate events by `request_id`; a repeated `request_id` SHALL be acknowledged
  200 and processed at most once.
- 3.3 WHEN a `person_detected` or `motion_detected` event is validated, THE SYSTEM SHALL push a
  notification to the resident's device(s) carrying event type, timestamp, deviceId, and `thumbnail_url`.
- 3.4 WHEN the app receives a person/motion push, THE SYSTEM SHALL play the event-type-specific haptic
  pattern (see FR-9) and display the visitor thumbnail full-bleed.
- 3.5 IF push delivery fails or is disabled, THE SYSTEM SHALL still surface the event on next app foreground
  via a backend poll of recent events.

### FR-4 — Live session (WebRTC)
- 4.1 WHEN the resident opens a session, THE SYSTEM SHALL establish a WebRTC connection negotiating audio as
  `sendrecv` and video as `recvonly`, mirroring the Ring sample's SDP shape.
- 4.2 WHILE a session is active, THE SYSTEM SHALL render inbound video and route inbound audio to the ASR
  pipeline (not to the phone speaker by default).
- 4.3 WHEN the resident ends the session OR the app is backgrounded > 30 s, THE SYSTEM SHALL close the peer
  connection and release the Ring session URL.
- 4.4 IF ICE/connection fails, THE SYSTEM SHALL show a reconnect state and retry connection setup up to 2
  times with backoff before surfacing "Couldn't connect to your doorbell."
- 4.5 THE SYSTEM SHALL position all UI overlays outside the top-left and top-right corners to avoid the
  mandatory Ring media watermark.

### FR-5 — Inbound captions (ASR)
- 5.1 WHILE a session is active in Clarity Mode, THE SYSTEM SHALL stream inbound audio to Amazon Transcribe
  streaming and SHALL render partial results as they arrive.
- 5.2 WHILE a session is active in Privacy Mode, THE SYSTEM SHALL transcribe inbound audio entirely
  on-device and SHALL NOT transmit any audio off the handset.
- 5.3 THE SYSTEM SHALL display each token with a visual confidence treatment: tokens below a 0.6 confidence
  threshold SHALL render visually de-emphasized (dimmed/italic) and SHALL never be styled as certain.
- 5.4 IF no speech is detected for ≥ 5 s while a person is present, THE SYSTEM SHALL show an explicit
  "No speech detected" state rather than an empty screen.
- 5.5 WHEN speaker turns change (detected by pause/segmentation), THE SYSTEM SHALL start a new labeled turn
  rather than concatenating text.

### FR-6 — Outbound reply (the defining capability)
- 6.1 WHEN the resident selects a Smart Reply or submits free text, THE SYSTEM SHALL synthesize speech and
  SHALL inject it into the outbound WebRTC audio track so it is audible at the doorbell.
- 6.2 THE SYSTEM SHALL implement outbound audio via the WebView audio pipeline (browser WebRTC +
  AudioContext → MediaStreamTrack) as the primary mechanism (see design; flutter_webrtc lacks Insertable
  Streams). A native platform-channel PCM path is the sole approved alternative.
- 6.3 WHILE reply audio is playing at the door, THE SYSTEM SHALL show a "Speaking at your door…" state and
  SHALL disable duplicate submission of the same reply.
- 6.4 IF outbound audio injection is unavailable at runtime, THE SYSTEM SHALL degrade to Captions-Only Mode
  (FR-12) and SHALL inform the resident that spoken replies are unavailable — it SHALL NOT silently fail.
- 6.5 THE SYSTEM SHALL append every sent reply to the conversation transcript as a `resident` turn with
  source `template` or `freetext`.

### FR-7 — Smart Replies
- 7.1 WHEN new visitor caption text is finalized, THE SYSTEM SHALL request ≤ 3 short contextual reply
  suggestions from Amazon Bedrock.
- 7.2 THE SYSTEM SHALL always present a fixed safe-reply set ("Please leave it at the door", "I can't come
  to the door right now", "Please come back later") even if Bedrock is unavailable.
- 7.3 IF Bedrock times out (> 2 s) or errors, THE SYSTEM SHALL silently fall back to the fixed set without
  blocking the reply bar.
- 7.4 THE SYSTEM SHALL send only transcript text (never audio/video) to Bedrock.

### FR-8 — Transcript persistence
- 8.1 WHEN a session ends, THE SYSTEM SHALL persist the conversation as ordered text turns with timestamps,
  speaker, source, and per-turn confidence.
- 8.2 THE SYSTEM SHALL make transcripts searchable by free text and filterable by date.
- 8.3 THE SYSTEM SHALL NOT persist raw audio or video at any time.
- 8.4 WHEN the resident deletes a transcript, THE SYSTEM SHALL remove it from device and backend within the
  same operation and confirm deletion.

### FR-9 — Haptic vocabulary
- 9.1 THE SYSTEM SHALL define at least three distinguishable vibration patterns: person-at-door, motion,
  conversation-started.
- 9.2 WHEN an event occurs, THE SYSTEM SHALL play the corresponding pattern; patterns SHALL be documented
  and user-viewable in Settings.
- 9.3 THE SYSTEM SHALL provide a screen-strobe + torch visual alert option as a software equivalent of a
  flashing-light doorbell.

### FR-10 — Settings
- 10.1 THE SYSTEM SHALL let the resident toggle Privacy Mode ↔ Clarity Mode; the change SHALL apply to the
  next session and SHALL be indicated during any active session.
- 10.2 THE SYSTEM SHALL let the resident set caption text size and contrast, and preview it live.
- 10.3 THE SYSTEM SHALL let the resident enable/disable each haptic pattern and the strobe/torch alert.
- 10.4 THE SYSTEM SHALL honor OS-level text-scaling and reduce-motion settings.

### FR-11 — Privacy zones
- 11.1 IF a device has configured privacy zones, THE SYSTEM SHALL NOT run visual processing on masked
  regions and SHALL NOT display masked pixels.

### FR-12 — Captions-Only degrade mode (fallback scope)
- 12.1 IF outbound audio injection is proven unavailable (spike fails or runtime error), THE SYSTEM SHALL
  operate as a captions-plus-visitor-facing-flow product: live captions of the visitor and an on-screen
  text/QR prompt the resident can surface, with all other features intact.
- 12.2 THE SYSTEM SHALL treat Captions-Only Mode as a first-class, fully-tested mode, not an error state.

---

## 5. Non-functional requirements

- NFR-1 (Performance): meet G1–G3 latency budgets on a mid-tier 2023 Android device and iPhone 12+.
- NFR-2 (Accessibility): WCAG 2.2 AA on every screen; all interactive elements labeled for TalkBack/
  VoiceOver; minimum 4.5:1 text contrast; no audio-only information; support dynamic type to 200%.
- NFR-3 (Security): OAuth secrets server-side only; tokens in secure enclave/secret store; TLS 1.2+ for all
  transport; HMAC verification on webhooks; no PII in logs.
- NFR-4 (Privacy): no raw audio/video persisted; Privacy Mode has zero audio egress (network assertion in
  tests).
- NFR-5 (Reliability): a single component failure (Bedrock, push, Transcribe) SHALL degrade gracefully, not
  crash a session (see error handling).
- NFR-6 (Scalability): backend webhook path SHALL be idempotent and horizontally stateless (state in a
  store, not memory) so it can run multiple instances.
- NFR-7 (Rate limits): never exceed 100 req/s to Ring; back off on 429.
- NFR-8 (Portability): Flutter app targets iOS 14+ and Android 8.0 (API 26)+.
- NFR-9 (Maintainability): all Ring/AWS integration behind interfaces; fixture implementations for offline
  demo and tests.

---

## 6. Acceptance test scenarios (traceability)

Each maps to requirements and is verified in the test strategy (design §Testing).

- AT-1 (FR-1): Link account; kill the access token; make a call → refresh happens once, call succeeds.
- AT-2 (FR-3): POST the same webhook `request_id` twice → single alert, both return 200 within 5 s.
- AT-3 (FR-4): Open session → SDP offer contains `a=sendrecv` audio and `a=recvonly` video.
- AT-4 (FR-5.3): Feed audio yielding a low-confidence token → token renders de-emphasized.
- AT-5 (FR-6.1/6.2): Tap a reply → measurable audio starts on the outbound track within 2 s (spike harness).
- AT-6 (FR-6.4): Force injection unavailable → app enters Captions-Only Mode with a visible notice, no crash.
- AT-7 (FR-7.3): Block Bedrock → fixed safe replies still present within 2 s.
- AT-8 (FR-8.3/NFR-4): Run a full session in Privacy Mode → assert zero audio bytes egress; assert no
  audio/video files written.
- AT-9 (NFR-2): Run each screen through an automated a11y scan + manual screen-reader pass → zero AA
  violations.
- AT-10 (FR-12): Full regression suite passes in Captions-Only Mode.
