# Requirements: Threshold (threshold-doorbell)

Two-way captioned Ring doorbell for deaf and hard-of-hearing residents.
Amazon Developer Hackathon 2026, Ring track, Flutter (iOS + Android) plus backend.

Acceptance criteria use EARS syntax (WHEN/IF/WHILE ... THE SYSTEM SHALL ...). Every requirement is atomic
and testable.

**Revision status.** All 23 defects raised in `SPEC_DESIGN_TASK_ANALYSIS.md` are resolved in this revision.
Resolved defect IDs are cited inline as `[R-n]`, `[D-n]`, `[T-n]`. Rather than claiming "no open questions"
as an unearned assertion, this document states explicitly: there are no known unresolved ambiguities as of
this revision, and any future ambiguity must be recorded in §7.

---

## 1. Overview and goals

Threshold turns a Ring video doorbell into a two-way, text-based conversation device for people who cannot
hear. When a visitor speaks, the resident sees live captions on their phone. When the resident taps or types
a reply, a synthesized voice is played out of the doorbell so the visitor hears it. The defining capability
is the **outbound reply through the doorbell**, built on Ring's bidirectional (`sendrecv`) WebRTC audio.

**Reference conditions (latency goals are only meaningful against these):**
- Reference device, Android: Google Pixel 7 (8 GB RAM, 2022/2023 mid-tier class).
- Reference device, iOS: iPhone 12 (exactly; not "12 or later") [R-3].
- Good network: at least 5 Mbps down, 2 Mbps up, round-trip time under 100 ms, no packet loss.

**Goals.** G1 is split into two independently controllable segments because the original end-to-end
formulation spanned systems outside our control and had no defined start instant [R-3].
- G1a. From **webhook receipt at our backend** (t0, the first instant under our control) to **push delivered
  to the device**: at most 1.5 s.
- G1b. From **resident tapping Open** to **first caption glyph rendered**: at most 2.0 s (Clarity Mode).
  User reaction time between G1a and G1b is explicitly excluded from both budgets.
- G2. Caption partial-result latency at most 1.0 s after speech onset (Clarity Mode).
- G3. Reply audible at the doorbell at most 2.0 s after tap (tap to audio-start).
- G4. Fully operable with device sound off and a screen reader on; WCAG 2.2 AA on all screens.
- G5. Zero doorstep audio leaves the device in Privacy Mode (verified by network assertion).

**Primary success definition.** A resident completes a full two-way exchange (visitor speaks, caption
appears, resident replies, reply is audible at the door, visitor responds, caption appears) without hearing,
in a live demo, without falling back to a mock.

---

## 2. Non-goals and out of scope

- N1. No open-ended conversational AI or chatbot persona. AI is limited to speech-to-text, text-to-speech,
  and at most 3 suggested replies.
- N2. No live language translation. (Language *selection* is in scope: FR-16.)
- N3. No sign-language gesture recognition.
- N4. No Fire TV or Alexa companion surface.
- N5. No user-account system of our own beyond Ring OAuth identity; no social features; no admin console.
- N6. No storage or replay of visitor audio or video. Only derived text is persisted.
- N7. No support for non-Ring doorbells.
- N8. Not a certified Ring App Store production release in the hackathon window; target is a demo-ready,
  staging-validated build.
- N9. **No visitor-facing display.** A Ring doorbell has no screen and the resident's phone is not visible to
  the visitor. Any feature requiring the visitor to *read* something is out of scope [R-1, D-1].

---

## 3. Personas and roles

| Role | Description | Capabilities |
|---|---|---|
| Resident (primary) | Deaf or HoH Ring owner. Persona: Priya, 34, profoundly deaf. | Receive alerts, open session, read captions, send replies, search history, configure settings. |
| Caretaker resident | Older HoH user. Persona: Bernard, 78. | Same as Resident; relies on scripted replies and larger text. |
| Visitor | Person at the door. Not an app user. | Heard (audio captured for captioning) and spoken to (reply audio at the door). No account, no UI, no display. |
| System/backend | Server components. | Webhooks, OAuth exchange and refresh, WebRTC signaling, Clarity-Mode ASR relay, Smart Replies, transcript storage. |

Exactly one authenticated human role exists (Resident). All resident-scoped data is keyed by `residentSub`
derived server-side from the session, never from client input [D-9].

---

## 4. Functional requirements

### FR-1: Ring account linking and unified auth recovery
- 1.1 WHEN the resident starts linking, THE SYSTEM SHALL initiate Ring OAuth 2.0 authorization-code flow
  with PKCE and a cryptographically random `state`.
- 1.2 WHEN Ring redirects back with a code, THE SYSTEM SHALL exchange it server-side and SHALL NOT expose
  the Ring client secret to the app.
- 1.3 IF the returned `state` does not match the issued value, THE SYSTEM SHALL reject the callback and
  SHALL display "Sign-in could not be verified. Please try again."
- 1.4 WHEN a Ring access token is within 120 s of expiry OR a Ring call returns 401, THE SYSTEM SHALL
  refresh using the refresh token and SHALL retry the original call exactly once.
- 1.5 **Unified auth-recovery flow** [R-6]. IF any authentication failure occurs (Ring refresh failure, or
  expiry of the app-to-backend session), THE SYSTEM SHALL execute one single recovery flow: preserve the
  current conversation and UI state locally, present exactly one non-destructive re-authentication prompt,
  and resume the interrupted action on success. There SHALL NOT be two separate recovery paths.
- 1.6 THE SYSTEM SHALL store Ring access and refresh tokens **only** server-side, as KMS-encrypted
  attributes in the datastore [D-7]. THE SYSTEM SHALL NOT store Ring tokens on the device; the device
  SHALL hold only the app-to-backend session credential in the platform secure store [D-6].
- 1.7 THE SYSTEM SHALL NOT write tokens, secrets, or session credentials to logs or shared preferences.

### FR-2: Device discovery
- 2.1 WHEN linking succeeds, THE SYSTEM SHALL fetch authorized Ring devices and capabilities and SHALL
  cache them for at most 24 h.
- 2.2 IF the account has zero compatible devices, THE SYSTEM SHALL display an explicit empty state
  explaining that a compatible Ring device is required. (Fixture-device loading is a test/demo concern
  specified in design §11, not a product requirement) [R-8].
- 2.3 THE SYSTEM SHALL respect the Ring rate limit of 100 requests per second using token-bucket
  throttling, with exponential backoff and jitter on 429 and 5xx.

### FR-3: Event ingestion and alerting
- 3.1 WHEN Ring POSTs a webhook, THE SYSTEM SHALL verify the HMAC signature in constant time and SHALL
  return HTTP 200 within 5 s.
- 3.2 THE SYSTEM SHALL deduplicate by `request_id`; a repeated `request_id` SHALL return 200 and SHALL be
  processed at most once.
- 3.3 WHEN a `person_detected` or `motion_detected` event is verified, THE SYSTEM SHALL push a notification
  carrying event type, timestamp, deviceId, and `thumbnail_url`.
- 3.4 WHEN the app receives the push, THE SYSTEM SHALL play the event-specific haptic pattern (FR-9) and
  display the thumbnail full-bleed.
- 3.5 IF push delivery fails or notifications are disabled, THE SYSTEM SHALL surface the event on next
  foreground via a paginated poll of recent events.

### FR-4: Live session
- 4.1 WHEN the resident opens a session, THE SYSTEM SHALL establish **exactly one** WebRTC peer connection,
  owned by the WebView runtime (design §2, decision ARCH-1), negotiating audio `sendrecv` and video
  `recvonly` [D-3].
- 4.2 WHILE a session is active, THE SYSTEM SHALL render inbound video and route inbound audio to the
  caption pipeline, and SHALL NOT route inbound audio to the phone speaker by default.
- 4.3 WHEN the resident ends the session, THE SYSTEM SHALL close the peer connection and release the Ring
  session URL.
- 4.3a WHILE the app is backgrounded, THE SYSTEM SHALL keep the session alive for up to 5 minutes so the
  resident can walk to the door or switch apps, and SHALL close it after 5 minutes of background or
  immediately on explicit end [R-10]. WHEN the app returns to foreground within that window, THE SYSTEM
  SHALL resume the session without re-negotiation where the connection is still alive.
- 4.4 IF connection setup fails, THE SYSTEM SHALL retry at most 2 times with backoff, then display
  "Couldn't connect to your doorbell."
- 4.5 THE SYSTEM SHALL keep UI overlays clear of the top-left and top-right corners to avoid the mandatory
  Ring watermark.
- 4.6 IF a new event arrives for the **same** device WHILE a session is active, THE SYSTEM SHALL update the
  current session context and replay the haptic, and SHALL NOT open a second session.
- 4.7 IF a new event arrives for a **different** device WHILE a session is active, THE SYSTEM SHALL queue it
  as a notification and SHALL NOT interrupt the active session. Exactly one live session SHALL exist at a
  time.
- 4.8 WHEN the app-to-backend session expires mid-use, THE SYSTEM SHALL apply the unified auth-recovery flow
  of FR-1.5 [R-6].

### FR-5: Inbound captions
- 5.1 WHILE a session is active in Clarity Mode, THE SYSTEM SHALL relay inbound audio to Amazon Transcribe
  streaming and SHALL render partial results as they arrive.
- 5.2 WHILE a session is active in Privacy Mode, THE SYSTEM SHALL transcribe inbound audio entirely
  on-device and SHALL NOT transmit audio or transcript text off the handset.
- 5.2a THE SYSTEM SHALL download the on-device speech model only after explicit resident opt-in over the
  network, SHALL display model size before download, and SHALL keep Privacy Mode unavailable and clearly
  labelled as unavailable until the model is present and verified [D-12]. Model download SHALL never occur
  during a live session.
- 5.3 WHILE a caption result is a **partial** (per-token confidence not available from the engine), THE
  SYSTEM SHALL render the whole partial in a provisional style (de-emphasized) and SHALL NOT style it as
  certain.
- 5.3a WHEN a caption result is **finalized** and per-token confidence is available, THE SYSTEM SHALL render
  tokens below 0.6 confidence de-emphasized and tokens at or above 0.6 in normal style.
- 5.4 **Presence definition** [R-2]. A visitor SHALL be considered present WHEN a session is active AND
  either a `person_detected` event for that device occurred within the last 60 s, OR the on-device visual
  processor (FR-11) currently reports at least one person. IF the visual processor is unavailable or
  disabled, the event condition alone SHALL determine presence. IF a visitor is present and no speech is
  detected for at least 5 s, THE SYSTEM SHALL display an explicit "No speech detected" state.
- 5.5 WHEN speaker turns change (pause or segmentation boundary), THE SYSTEM SHALL start a new labeled turn
  rather than concatenating text.
- 5.6 **Self-transcription suppression** [R-9, D-8]. WHILE reply audio is playing at the door, THE SYSTEM
  SHALL gate the caption pipeline so the doorbell microphone return of our own synthesized speech is not
  transcribed, SHALL keep the gate closed for a 300 ms tail after playback ends, and SHALL mark the gated
  interval in the transcript as a non-visitor gap. THE SYSTEM SHALL additionally enable WebRTC echo
  cancellation on the inbound audio track.
- 5.7 IF a session ends while an utterance is still unfinalized, THE SYSTEM SHALL persist the partial text
  with `confidence: null` and `provisional: true` [R-7].

### FR-6: Outbound reply (the defining capability)
- 6.1 WHEN the resident selects a Smart Reply or submits free text, THE SYSTEM SHALL synthesize speech and
  inject it into the outbound WebRTC audio track so it is audible at the doorbell.
- 6.2 THE SYSTEM SHALL implement outbound audio in the WebView runtime using
  `AudioContext` to `MediaStreamAudioDestinationNode` to `RTCRtpSender.replaceTrack` (design §2, ARCH-1).
  A native platform-channel PCM source is the sole approved alternative.
- 6.3 WHILE reply audio is playing, THE SYSTEM SHALL display "Speaking at your door" and SHALL disable
  resubmission of the same reply.
- 6.4 IF outbound audio is unavailable, THE SYSTEM SHALL enter Captions-Only Mode (FR-12), SHALL state that
  spoken replies are unavailable, and SHALL NOT fail silently.
- 6.4a **Capability probe** [D-2]. AT session start, after the peer connection reaches `connected`, THE
  SYSTEM SHALL run the probe specified in design §5.1: emit at most 200 ms of near-silent audio (at or below
  -60 dBFS, inaudible at the door) through the outbound track and confirm via `RTCRtpSender.getStats()` that
  `packetsSent` for the audio sender increases above baseline within 1000 ms. Success SHALL set
  `outboundAvailable = true`. Failure, timeout, or unavailable statistics SHALL set it to `false`.
- 6.4b The probe result SHALL be **sticky for the whole session**. IF a later injection attempt fails, THE
  SYSTEM SHALL degrade that session to Captions-Only for its remainder and SHALL NOT auto-recover within the
  session. The next session SHALL re-probe from scratch.
- 6.5 THE SYSTEM SHALL append every sent reply to the transcript as a `resident` turn with source `template`
  or `freetext`.

### FR-7: Smart Replies
- 7.1 WHILE in **Clarity Mode**, WHEN visitor caption text is finalized, THE SYSTEM SHALL request at most 3
  short contextual suggestions from Amazon Bedrock, sending transcript text only.
- 7.1a WHILE in **Privacy Mode**, THE SYSTEM SHALL NOT call Bedrock and SHALL NOT send transcript text off
  the device; suggestions SHALL be produced on-device from the fixed safe set plus local keyword-matched
  templates [R-4]. Settings SHALL state this difference plainly.
- 7.2 THE SYSTEM SHALL always offer the fixed safe-reply set: "Please leave it at the door", "I can't come
  to the door right now", "Please come back later".
- 7.3 IF Bedrock exceeds a 2 s timeout or errors, THE SYSTEM SHALL fall back to the fixed set without
  blocking the reply bar.
- 7.4 THE SYSTEM SHALL never send audio or video to Bedrock.
- 7.5 THE SYSTEM SHALL always render the reply bar with at least the fixed safe set; the reply bar SHALL
  never appear empty, and free-text input SHALL always be available.

### FR-8: Transcript persistence
- 8.1 WHEN a session ends, THE SYSTEM SHALL persist the conversation as ordered text turns with timestamp,
  speaker, source, confidence (nullable per FR-5.7), and provisional flag.
- 8.2 THE SYSTEM SHALL make transcripts searchable by free text and filterable by date, using paginated
  results (design §4) [D-10].
- 8.3 THE SYSTEM SHALL NOT persist raw audio or video at any time.
- 8.4 WHEN the resident deletes a transcript, THE SYSTEM SHALL remove it from device and backend in the same
  operation and SHALL confirm deletion.
- 8.5 THE SYSTEM SHALL retain transcripts for 90 days by default, then delete automatically by TTL; the
  retention period SHALL be visible in Settings.
- 8.6 THE SYSTEM SHALL provide "Delete all my data", erasing all transcripts for the resident from device
  and backend and revoking stored Ring tokens, behind a confirmation step.
- 8.7 THE SYSTEM SHALL derive `residentSub` for every read and write from the authenticated session and
  SHALL reject any client-supplied `residentSub` [D-9].

### FR-9: Haptic and visual alerts
- 9.1 THE SYSTEM SHALL implement **exactly three** distinguishable vibration patterns in v1:
  person-at-door, motion, conversation-started [R-11].
- 9.2 WHEN an event occurs, THE SYSTEM SHALL play the corresponding pattern, and SHALL display the pattern
  reference in Settings.
- 9.3 THE SYSTEM SHALL offer a screen-strobe and torch visual alert as a software equivalent of a
  flashing-light doorbell.
- 9.4 THE SYSTEM SHALL cap strobe and torch flashing at no more than 3 flashes per second (WCAG 2.2
  SC 2.3.1), and SHALL keep it off by default requiring explicit opt-in.

### FR-10: Settings
- 10.1 THE SYSTEM SHALL let the resident switch Privacy Mode and Clarity Mode. The change SHALL apply to
  the next session, and any active session SHALL display which mode it is running.
- 10.2 THE SYSTEM SHALL let the resident adjust caption text size and contrast within a bounded range whose
  minimum contrast is 4.5:1, so no user setting can breach NFR-2 [R-12].
- 10.3 THE SYSTEM SHALL let the resident enable or disable each haptic pattern and the strobe/torch alert.
- 10.4 THE SYSTEM SHALL honor OS text-scaling and reduce-motion settings.

### FR-11: Privacy zones and visual context
- 11.1 IF a device has privacy zones, THE SYSTEM SHALL NOT run visual processing on masked regions and
  SHALL NOT display masked pixels.
- 11.2 THE SYSTEM SHALL run all visual processing on-device and SHALL NOT transmit frames off the handset.

### FR-12: Captions-Only Mode (receive-only fallback)
Rewritten to be physically coherent. A Ring doorbell has no screen and the visitor cannot see the
resident's phone, so no visitor-facing prompt is possible (N9) [R-1, D-1, T-5].
- 12.1 IF outbound audio is unavailable, THE SYSTEM SHALL operate **receive-only**: live captions of the
  visitor, alerts, visual context, transcript persistence, history, and settings all remain fully
  functional; only spoken replies are unavailable.
- 12.2 THE SYSTEM SHALL display a persistent, non-alarming banner stating "Replies unavailable on this
  device. You can still see what your visitor says."
- 12.3 THE SYSTEM SHALL offer the resident, in Captions-Only Mode, a one-tap action to open the official
  Ring app for two-way talk, so a hearing household member or the resident's own chosen method can respond.
  THE SYSTEM SHALL NOT claim to send audio itself in this mode.
- 12.4 THE SYSTEM SHALL treat Captions-Only Mode as a first-class, fully tested mode, not an error state,
  and the full regression suite SHALL pass in it.

### FR-13: Permissions and consent flows
- 13.1 THE SYSTEM SHALL request only: notifications, microphone (required by the WebRTC runtime to negotiate
  a `sendrecv` audio track), and vibration where the platform requires declaration. Camera SHALL NOT be
  requested; the outbound track is synthesized, not captured [D-6 clarification].
- 13.2 WHEN a permission is needed, THE SYSTEM SHALL request it in-context with a plain-language rationale
  immediately before first use, not at launch.
- 13.3 IF a permission is denied, THE SYSTEM SHALL keep every unaffected feature usable and SHALL explain
  what is unavailable without blocking.
- 13.4 IF a permission is permanently denied, THE SYSTEM SHALL show a one-tap deep link to OS app settings
  and SHALL NOT re-prompt repeatedly.
- 13.5 IF notifications are denied, THE SYSTEM SHALL fall back to the foreground poll (FR-3.5) and state
  that live alerts are unavailable until enabled.

### FR-14: Visitor recording notice and compliance
- 14.1 THE SYSTEM SHALL present, on first use and in Settings, a plain-language notice that Threshold
  transcribes what visitors say, and SHALL require one-time acknowledgement.
- 14.2 THE SYSTEM SHALL document in-product and in the privacy policy that no visitor audio or video is
  stored, that Privacy Mode transcribes on-device only, and that the resident is the data controller
  responsible for lawful use in their jurisdiction.
- 14.3 THE SYSTEM SHALL offer an optional, default-off audible notice played at the door at session start
  via the outbound-audio path.
- 14.3a **Compliance fallback when outbound audio is unavailable** [R-5]. IF the resident has enabled the
  audible notice but outbound audio is unavailable (Captions-Only Mode), THE SYSTEM SHALL NOT silently
  transcribe. It SHALL present a choice: continue with captions without the audible notice (acknowledging
  responsibility), or disable transcription for that session. THE SYSTEM SHALL honor the choice for the
  whole session and SHALL remember the default.
- 14.4 THE SYSTEM SHALL treat visitor-spoken text as personal data for retention and erasure (FR-8.5, 8.6).

### FR-15: Connectivity and offline behavior
- 15.1 IF the app opens with no connectivity, THE SYSTEM SHALL allow viewing and searching locally cached
  transcripts and SHALL show a clear offline state for network features.
- 15.2 WHILE offline, THE SYSTEM SHALL disable backend and Ring actions (opening a session, linking) with an
  explanatory state rather than silent failure.
- 15.3 WHEN connectivity returns, THE SYSTEM SHALL restore online capability without an app restart.
- 15.4 IF the backend is unreachable while connectivity exists, THE SYSTEM SHALL state that live sessions are
  temporarily unavailable, because signaling requires the backend (design §1, accepted single point of
  failure) [D-5], and SHALL keep cached history usable.

### FR-16: Language and locale
- 16.1 THE SYSTEM SHALL let the resident select the caption recognition language, defaulting to the device
  locale when supported and to `en-US` otherwise [R-13].
- 16.2 THE SYSTEM SHALL document the supported language set per mode, noting that Clarity Mode and Privacy
  Mode may support different sets.
- 16.3 IF the selected language is unsupported in the active mode, THE SYSTEM SHALL state this before the
  session starts and SHALL offer a supported alternative.

### FR-17: External contract drift
- 17.1 THE SYSTEM SHALL isolate all Ring request and response parsing behind a single adapter layer with
  schema validation, so an unexpected payload produces a typed, logged, non-fatal error rather than a crash
  [R-14].
- 17.2 IF a Ring response fails schema validation, THE SYSTEM SHALL degrade the affected feature, keep the
  session alive where possible, and record a diagnostic event.

---

## 5. Non-functional requirements

- NFR-1 (Performance): meet G1a, G1b, G2, G3 on the reference devices under reference conditions, verified
  by an automated latency harness (task 25).
- NFR-2 (Accessibility): WCAG 2.2 AA on every screen; all interactive elements labeled for TalkBack and
  VoiceOver; minimum 4.5:1 text contrast enforced even against user settings (FR-10.2); no audio-only
  information; dynamic type to 200%.
- NFR-3 (Security): Ring secrets server-side only; Ring tokens KMS-encrypted at rest and never on device;
  TLS 1.2 or higher on all transport; constant-time HMAC verification; no PII, tokens, or transcript text in
  logs; every resident-scoped operation authorized from the session, not client input.
- NFR-4 (Privacy): no raw audio or video persisted; in Privacy Mode neither audio nor transcript text leaves
  the handset (network assertion in tests).
- NFR-5 (Reliability): failure of Bedrock, push, Transcribe, or the visual processor SHALL degrade
  gracefully without ending a session. Backend unreachability SHALL prevent only new sessions (FR-15.4).
  Verified by an explicit degradation matrix (task 26).
- NFR-6 (Scalability): webhook path idempotent and horizontally stateless; all state in the datastore.
- NFR-7 (Rate limits): never exceed 100 requests per second to Ring; back off on 429.
- NFR-8 (Portability): iOS 14 or later; Android 8.0 (API 26) or later.
- NFR-9 (Maintainability): all Ring and AWS integrations behind interfaces with fixture implementations.
- NFR-10 (UI copy): no em-dash or en-dash characters in any user-facing string, enforced by a CI lint gate
  (steering/structure.md, task 29) [T-11].

---

## 6. Acceptance test scenarios

Verified per the strategy in design §9 ("Testing strategy and acceptance criteria").

- AT-1 (FR-1.1 to 1.7): Link account; expire the Ring access token; a call triggers exactly one refresh and
  succeeds. Assert no Ring token is present in device storage.
- AT-2 (FR-3.1, 3.2): POST the same webhook `request_id` twice; one alert, both 200 within 5 s.
- AT-3 (FR-4.1): Session offer contains `a=sendrecv` audio and `a=recvonly` video, and exactly one peer
  connection exists.
- AT-4 (FR-5.3, 5.3a): Partial renders provisional; finalized token below 0.6 renders de-emphasized; at or
  above 0.6 renders normal.
- AT-5 (FR-6.1, 6.2): Tap a reply; measurable audio energy appears on the outbound track within 2 s.
- AT-6 (FR-6.4, 6.4a, 6.4b): Probe fails at start, session is Captions-Only throughout; probe succeeds then
  injection fails mid-session, session stays Captions-Only, next session re-probes.
- AT-7 (FR-7.3, 7.5): Block Bedrock; fixed safe replies present within 2 s; reply bar never empty.
- AT-8 (FR-5.2, 8.3, NFR-4): Full Privacy-Mode session asserts zero audio and zero transcript-text egress,
  and no audio or video artifacts on disk.
- AT-9 (NFR-2): Every screen passes an automated a11y scan plus a manual screen-reader pass, zero AA
  violations; caption contrast cannot be set below 4.5:1.
- AT-10 (FR-12.4): Full regression suite passes in Captions-Only Mode.
- AT-11 (FR-4.6, 4.7): Same-device event updates context with no second session; different-device event
  queues; exactly one live session exists.
- AT-12 (FR-1.5, 4.8): Expire the backend session mid-action; exactly one recovery prompt appears, state is
  preserved, the action resumes. Assert no second divergent recovery path is reachable.
- AT-13 (FR-13): Deny each permission; dependent features degrade gracefully; permanently-denied shows the
  settings deep link without re-prompting; camera is never requested.
- AT-14 (FR-14.1, 14.3, 14.3a): First-run notice gates use; audible notice plays at session start when
  available; when unavailable the resident is offered continue-without-notice or disable-transcription, and
  the choice holds for the session.
- AT-15 (FR-8.5, 8.6): A transcript past 90 days is auto-deleted; "Delete all my data" erases transcripts
  and revokes tokens after confirmation.
- AT-16 (FR-9.4): Strobe flash rate measures at most 3 flashes per second and is off by default.
- AT-17 (FR-15): Offline launch allows cached history and disables network actions with explanation; going
  online restores capability without restart.
- AT-18 (FR-5.6): While a reply plays, the synthesized speech returning on the inbound leg is not
  transcribed, the gate reopens within 300 ms after playback, and the transcript marks the gap.
- AT-19 (FR-8.2, 8.7, D-10): Transcript and event lists paginate with a stable cursor; a request supplying a
  foreign `residentSub` is rejected and returns only session-scoped data.
- AT-20 (FR-15.4, NFR-5): With the backend unreachable, the app states live sessions are unavailable, keeps
  cached history usable, and does not crash. The degradation matrix passes for each dependency.
- AT-21 (FR-5.2a): Privacy Mode is unavailable and labelled so until the model is downloaded after explicit
  opt-in; no download is attempted during a live session.
- AT-22 (FR-16): Locale default is applied; an unsupported language is reported before session start with a
  supported alternative offered.
- AT-23 (FR-17): A malformed Ring payload produces a typed logged error and degrades the feature without
  crashing or ending the session.
- AT-24 (NFR-10): CI fails when an em-dash or en-dash is introduced into a UI string resource.
- AT-25 (FR-4.3a): Backgrounding for under 5 minutes preserves the session and it resumes on foreground;
  beyond 5 minutes it closes and releases the session URL.

---

## 7. Known open items

Any ambiguity discovered during implementation must be recorded here with a date and an owner before code
is written against an assumption. This section replaces the previous unearned "no open questions" assertion
[D-13].

- 2026-10-10, ARCH-1 spike outcome (owner: unassigned). The go/no-go outbound-audio spike (task 2) has not
  been run against a real Ring WebRTC session. The spike page `app/spike/webrtc_audio_spike.html` was
  executed only in a headless Chromium browser against its own offline loopback peer. Under those
  conditions the capability probe reported "outbound audio WORKS" and a silent-track control sent 0
  packets, so the probe does discriminate in that setting. However the spike has never run against Ring or
  inside the app (there is no in-app WebView), and its "speak" path plays a 440 Hz tone rather than a
  text-to-speech sample, so the TTS injection path is unproven (LOW-44). Task 2 therefore remains open: a
  real Ring session on a device or emulator is required before the two-way audio capability can be
  considered verified.
