# Design: Threshold (threshold-doorbell)

Implementation-ready technical design. Every failure mode has defined behavior.

**Revision status.** Resolves all design defects from `SPEC_DESIGN_TASK_ANALYSIS.md`. The two blocking
architectural questions are now decided: **ARCH-1** (single WebRTC stack) and **§5.1** (capability probe).
Known open items are tracked in §12; that section is no longer an unearned "none".

---

## 1. System architecture

```
┌──────────────┐  ONE WebRTC peer connection (WHEP)   ┌──────────────────────────────────┐
│  Ring device │  audio sendrecv | video recvonly     │  Flutter app (iOS 14+/Android 8+)│
│  (doorbell)  │◄────────────────────────────────────►│                                  │
└──────┬───────┘        owned by the WebView          │  WebView runtime (ARCH-1)        │
       │ webhooks                                     │   ├─ RTCPeerConnection           │
       │                                              │   ├─ inbound video render        │
       ▼                                              │   ├─ inbound audio tap -> PCM    │
┌───────────────────────────────┐                     │   └─ outbound AudioContext inject│
│ Backend (Node 20 + Fastify)   │◄───── HTTPS/WSS ────│  Flutter layer                   │
│  stateless, >=2 instances     │                     │   ├─ UI (Riverpod) overlays      │
│   ├─ /oauth/*                 │                     │   ├─ CaptionEngine (Clarity|Priv)│
│   ├─ /webhook (HMAC, idem)    │                     │   ├─ ReplyController + TTS       │
│   ├─ /devices /events (paged) │                     │   ├─ HapticService               │
│   ├─ /signaling (WS broker)   │                     │   └─ On-device: Whisper, ML Kit   │
│   ├─ /asr/stream (Clarity)    │                     └──────────────────────────────────┘
│   ├─ /replies (Bedrock)       │
│   ├─ /transcripts (paged)     │   AWS: Transcribe streaming, Bedrock, KMS,
│   └─ /me/data (erasure)       │        DynamoDB, Secrets Manager (app secrets only)
└───────────────────────────────┘
```

**ARCH-1 (decision): one peer connection, owned by the WebView.** [D-3]
The live session runs entirely inside an in-app WebView because only the browser runtime can inject
synthesized audio into an outbound track (`AudioContext` to `MediaStreamAudioDestinationNode` to
`RTCRtpSender.replaceTrack`). `flutter_webrtc` is **not** used for the live session and is removed from the
dependency set; it cannot inject outbound audio (no Insertable Streams on any platform) and running it
alongside the WebView would create two concurrent sessions to one Ring device.

Consequences, accepted deliberately:
- Inbound **video** renders inside the WebView surface; Flutter draws captions and controls as overlays on
  top using a `Stack`. Overlays stay clear of the watermark corners (FR-4.5).
- Inbound **audio** is tapped in the WebView via a `MediaStreamAudioSourceNode` plus
  `AudioWorkletNode`, producing 16 kHz mono PCM frames. Frames go to Clarity (backend WS) or are passed to
  Flutter over the JS bridge for Privacy Mode.
- The JS bridge is a performance-sensitive path. Budget and verification belong to the latency harness
  (task 23). If PCM bridging to Dart proves too slow for Privacy Mode on the reference devices, Privacy Mode
  runs its inference inside the WebView using a WASM build instead; this substitution does not affect any
  requirement because FR-5.2 only mandates that audio never leaves the handset.
- The native platform-channel PCM source remains the only approved alternative if the WebView path fails.

**Trust boundary.** The app never holds the Ring client secret or Ring tokens. Privileged calls (OAuth
exchange and refresh, Transcribe, Bedrock) run on the backend. In Privacy Mode no audio and no transcript
text leave the device; the backend is still used for signaling and events, so the earlier claim that Privacy
Mode "touches no backend" is withdrawn as inaccurate [D-4].

**Accepted single point of failure.** `/signaling` is required to start any session, including Privacy Mode.
A backend outage therefore prevents new sessions. This is accepted rather than mitigated for v1, is surfaced
to the resident by FR-15.4, and is covered by AT-20 [D-5].

---

## 2. Technology decisions

| Layer | Choice | Version | Why |
|---|---|---|---|
| App shell | Flutter / Dart | Flutter >= 3.24, Dart >= 3.4 | One codebase, both platforms; mobile is intrinsic. |
| State | `flutter_riverpod` | ^2.6.0 | Compile-safe DI, testable, fixtures injectable. |
| **Live session** | **`webview_flutter` + browser WebRTC** | ^4.7.0 | ARCH-1. Only runtime able to inject outbound audio. |
| ~~Inbound WebRTC~~ | ~~`flutter_webrtc`~~ | removed | Cannot inject outbound audio; would duplicate the session. |
| TTS | `flutter_tts` | ^4.2.0 | `synthesizeToFile` yields WAV/PCM to feed the bridge. |
| Cloud ASR | Amazon Transcribe streaming | current | Built for live captions; anchors AWS Builder. |
| On-device ASR | whisper.cpp (`whisper_ggml` or FFI), or WASM in WebView per ARCH-1 | current | Privacy Mode. Stretch; Clarity is default. |
| Smart replies | Amazon Bedrock (Clarity only) | current | Short suggestions. Not called in Privacy Mode (FR-7.1a). |
| Visual context | `google_mlkit_object_detection` | ^0.14.0 | On-device cues; frames never leave the phone. |
| Haptics | `vibration` | ^2.0.0 | Three distinct patterns. |
| Permissions | `permission_handler` | ^11.x | In-context requests, permanently-denied handling. |
| Connectivity | `connectivity_plus` | ^6.x | Offline detection and restore. |
| Push | `firebase_messaging` | ^15.x | FCM, APNs via FCM. |
| Backend | Node 20 LTS + Fastify | ^4.28 | Schema-validated routes, AWS SDK v3. |
| Datastore | DynamoDB + KMS | current | Stateless backend; **holds KMS-encrypted Ring tokens** [D-7]. |
| Secrets | AWS Secrets Manager | current | **Application secrets only** (Ring client secret, HMAC key, KMS key id). Not per-user tokens. |

**Version policy** [D-14]. The pins above are the versions this design is written against and are
authoritative. Upgrades are a deliberate change, not a build-time decision; the previous "verify latest at
build" caveat is withdrawn. CI pins via lockfiles.

**Rejected.** `flutter_webrtc` for the live session (cannot inject audio); two concurrent peer connections
(Ring session limits, double cost); per-user tokens in Secrets Manager (pricing and throttling are wrong for
per-user rows); any visitor-facing display (no hardware to show it, N9); persisting audio or video (N6).

---

## 3. Data models and schema

```ts
type DeviceId = string;
type EventType = 'motion_detected' | 'person_detected';
type Speaker = 'visitor' | 'resident';
type TurnSource = 'transcribe' | 'ondevice' | 'template' | 'freetext';
type CaptionMode = 'clarity' | 'privacy';

interface Device {
  id: DeviceId; name: string; capabilities: string[];
  privacyZones: BoundingBox[]; cachedAt: string;       // TTL 24h
}
interface BoundingBox { x: number; y: number; width: number; height: number; }

interface DoorEvent {
  eventId: string; requestId: string;                   // requestId = idempotency key
  type: EventType; deviceId: DeviceId; timestamp: string;
  confidence: number | null; boundingBox: BoundingBox | null;
  thumbnailUrl: string | null; processedAt: string | null;
}

interface Turn {
  turnId: string; speaker: Speaker; text: string;
  confidence: number | null;      // null when unfinalized (FR-5.7)
  provisional: boolean;           // true when persisted unfinalized (FR-5.7)
  timestamp: string; source: TurnSource;
}

interface Conversation {
  conversationId: string; deviceId: DeviceId;
  residentSub: string;            // ALWAYS server-derived from session (FR-8.7)
  startedAt: string; endedAt: string | null;
  mode: CaptionMode;
  outboundAvailable: boolean;     // probe result, sticky for session (FR-6.4a/b)
  language: string;               // BCP-47, FR-16
  turns: Turn[];
  expiresAt: string;              // startedAt + 90d, DynamoDB TTL (FR-8.5)
}

interface RingTokenRecord {       // backend only; never on device (FR-1.6)
  residentSub: string;
  accessTokenEnc: string;        // KMS-encrypted
  refreshTokenEnc: string;       // KMS-encrypted
  expiresAt: string;
}
```

**Tables.**
- `events`: PK `requestId`, conditional put enforces idempotency, TTL 7 days.
- `conversations`: PK `residentSub`, SK `conversationId`, GSI on `startedAt` for date filtering, TTL on
  `expiresAt`. Text turns only.
- `ring_tokens`: PK `residentSub`, KMS-encrypted token attributes [D-7].
- Erasure (FR-8.6) deletes all `conversations` for the `residentSub` and the `ring_tokens` row in one
  transaction.

---

## 4. API contracts

Error envelope on all 4xx and 5xx: `{ "error": { "code", "message", "requestId" } }`.
**Pagination** on all list endpoints: `?limit` (default 25, max 100) and `?cursor`; responses are
`{ items: T[], nextCursor: string | null }` [D-10].
**Authorization:** every session-authenticated route derives `residentSub` server-side; a client-supplied
`residentSub` is ignored and the request is rejected if it conflicts [D-9].

| Method | Path | Auth | Success | Errors |
|---|---|---|---|---|
| GET | `/oauth/start` | none | 302 to Ring authorize (PKCE + state) | 500 `oauth_init_failed` |
| GET | `/oauth/callback` | none | 302 to app deep link, sets session | 400 `state_mismatch`, 400 `code_exchange_failed` |
| POST | `/oauth/refresh` | session | 200 `{ expiresAt }` | 401 `refresh_failed` |
| GET | `/devices` | session | 200 `{ items: Device[], nextCursor }` | 401, 429 `rate_limited`, 502 `ring_unavailable`, 502 `ring_contract_invalid` |
| GET | `/events?since&limit&cursor` | session | 200 `{ items: DoorEvent[], nextCursor }` | 401, 429, 502 |
| POST | `/webhook` | HMAC | 200 `{ ok: true }` within 5 s | 401 `bad_signature`; duplicates return 200 |
| WS | `/signaling` | session | `{ sdpAnswer, sessionUrl }` | close 4401 unauth, 4408 timeout, 4409 `session_already_active` |
| WS | `/asr/stream` | session | `{ partial \| final, tokens[] }` | close 4401, 4500 `transcribe_error` |
| POST | `/replies` | session | 200 `{ suggestions: string[0..3] }` | 200 with fixed set on Bedrock error/timeout |
| GET | `/transcripts?query&from&to&limit&cursor` | session | 200 `{ items: Conversation[], nextCursor }` | 401 |
| POST | `/transcripts` | session | 201 `{ conversationId }` (server sets `residentSub`) | 401, 400 `schema`, 403 `resident_mismatch` |
| DELETE | `/transcripts/:id` | session | 204 | 401, 404 |
| DELETE | `/me/data` | session | 204 (transcripts erased, tokens revoked) | 401 |

**Webhook handling.** Verify HMAC over the raw body in constant time using the Secrets Manager key; on
mismatch return 401 without processing or logging the body. On success, conditional-put by `requestId`; if
the item exists, return 200 immediately. Acknowledge 200 first, then enqueue push asynchronously so the 5 s
budget is never at risk.

**Ring adapter.** All Ring responses pass schema validation in one adapter layer (FR-17). A validation
failure yields `ring_contract_invalid`, degrades the affected feature, and records a diagnostic event.

---

## 5. State machines and the capability probe

### 5.1 Capability probe specification [D-2]
Runs once per session, after `RTCPeerConnection.connectionState === 'connected'`, before the reply bar is
enabled.

1. Read baseline `packetsSent` for the audio `RTCRtpSender` via `getStats()`.
2. Build an `AudioContext`; create a `GainNode` with gain set so output is at or below **-60 dBFS**
   (inaudible at the door); feed it a 200 ms oscillator or silent buffer.
3. Connect through a `MediaStreamAudioDestinationNode`; call `sender.replaceTrack(destination.stream
   .getAudioTracks()[0])`.
4. Poll `getStats()` every 100 ms for up to **1000 ms**. If `packetsSent` exceeds baseline, the probe
   succeeds.
5. On success set `outboundAvailable = true` and restore the idle (silent) track. On failure, timeout, or
   missing statistics set `outboundAvailable = false`.

The result is **sticky for the session** (FR-6.4b). The probe is deliberately near-silent so a stranger at
the door never hears a test tone.

### 5.2 Session lifecycle
```
IDLE -> CONNECTING -> PROBING -> LIVE(two-way | captions-only)
          | fail x2        |                 |
          v                v                 v
        ERROR        (probe fail ->     BACKGROUNDED(<=5min) -> LIVE
                      captions-only)          | >5min
                                              v
                                           CLOSING -> IDLE
```
- `net drop` from LIVE enters RECONNECTING; success returns to LIVE with the same sticky mode; two failures
  go to CLOSING.
- Privacy Mode keeps captioning locally during RECONNECTING; video and replies are affected.
- Background handling per FR-4.3a: up to 5 minutes alive, resume without renegotiation when possible [R-10].

### 5.3 Reply lifecycle
```
COMPOSING -> SYNTHESIZING -> GATE_ASR_ON -> SPEAKING_AT_DOOR -> GATE_OFF(+300ms) -> SENT(logged)
                  | tts fail                      | inject fail
                  v                               v
            ERROR(retry once)      DEGRADE to captions-only for rest of session + banner
```
- `GATE_ASR_ON` and `GATE_OFF` implement self-transcription suppression (FR-5.6) [D-8, D-11].
- If the visitor speaks during `SPEAKING_AT_DOOR`, that audio is intentionally not transcribed; the gap is
  marked in the transcript so the resident knows something may have been missed.
- The reply bar is disabled entirely when `outboundAvailable === false` (Captions-Only banner shown instead).

### 5.4 Caption mode
`clarity` and `privacy` switch only between sessions (FR-10.1). A mid-session request is queued and applied
next session, with the active mode always displayed.

---

## 6. Error handling and edge cases

| Condition | Behavior |
|---|---|
| OAuth state mismatch | Reject, FR-1.3 message, no token stored. |
| Ring token expiring or 401 | Refresh once, retry once (FR-1.4). |
| Any auth failure (refresh or session expiry) | Single unified recovery flow, state preserved, action resumed (FR-1.5) [R-6]. |
| Ring 429 | Token bucket plus backoff with jitter; never exceed 100 rps. |
| Ring 5xx | Retry at most 2, then `ring_unavailable`; cached devices read-only. |
| Ring payload fails schema | `ring_contract_invalid`, degrade feature, keep session, log diagnostic (FR-17). |
| Duplicate webhook | Idempotent 200, processed once. |
| Bad webhook signature | 401, dropped, body not logged. |
| Push fails or denied | Foreground paginated poll (FR-3.5, FR-13.5). |
| Connect fails | Retry at most 2, then session error (FR-4.4). |
| Second session attempted | `/signaling` returns 4409; app enforces one live session (FR-4.6, 4.7). |
| Background under 5 min | Session preserved, resumes on foreground (FR-4.3a). |
| Background over 5 min | Close, release session URL (FR-4.3a). |
| Probe fails | Captions-Only for the whole session, banner shown (FR-6.4a, 12.2). |
| Injection fails mid-session | Degrade to Captions-Only for remainder, no auto-recovery (FR-6.4b). |
| Reply audio returning on inbound leg | ASR gated plus 300 ms tail, gap marked, echo cancellation on (FR-5.6). |
| Partial caption | Whole partial provisional (FR-5.3). |
| Finalized low-confidence token | De-emphasized below 0.6 (FR-5.3a). |
| Session ends mid-utterance | Persist partial text, `confidence: null`, `provisional: true` (FR-5.7). |
| Visitor present, no speech 5 s | "No speech detected" using the FR-5.4 presence definition. |
| Transcribe WS drop | Reconnect, replay at most 2 s buffered audio. **Do not switch mode mid-session** (FR-10.1); if reconnect fails, end captions with an explicit notice and suggest Privacy Mode for the *next* session [D-15]. |
| Bedrock timeout or error | Fixed safe set within 2 s (FR-7.3, 7.5). |
| Privacy Mode active | Bedrock not called; on-device suggestions only (FR-7.1a). |
| Privacy Mode model absent | Mode unavailable and labelled; opt-in download outside any session (FR-5.2a). |
| Backend unreachable | New sessions unavailable with explanation; cached history usable (FR-15.4). |
| Offline launch | Cached history usable; network actions disabled with explanation (FR-15.1, 15.2). |
| Privacy zones present | No processing or display of masked regions (FR-11.1). |
| Unsupported language for mode | Stated before session start, alternative offered (FR-16.3). |
| Audible notice enabled but unavailable | Offer continue-without-notice or disable-transcription (FR-14.3a) [R-5]. |
| Client sends foreign `residentSub` | 403 `resident_mismatch`; server-derived value always wins (FR-8.7). |
| List endpoint large result | Cursor pagination, max 100 per page (D-10). |
| Strobe enabled | Capped at 3 flashes per second, off by default (FR-9.4). |
| Transcript older than 90 days | TTL auto-delete (FR-8.5). |
| "Delete all my data" | Transcripts erased and tokens revoked in one transaction (FR-8.6). |

---

## 7. Security and authorization

- OAuth 2.0 authorization code with PKCE; `state` CSRF check; secret exchange server-side only.
- App-to-backend session: HttpOnly, Secure, SameSite=strict cookie or signed bearer; 30 minute idle expiry;
  bound to `residentSub`. Expiry follows the unified recovery flow (FR-1.5).
- **Authorization, not just authentication:** every resident-scoped read and write derives `residentSub` from
  the session. Client-supplied identifiers are ignored or rejected with 403 [D-9]. Covered by AT-19.
- Ring tokens: KMS-encrypted attributes in `ring_tokens`; **never** stored on the device [D-6, D-7]. Secrets
  Manager holds only application secrets.
- Transport: TLS 1.2 or higher; WSS for signaling and ASR.
- Webhooks: constant-time HMAC verification.
- Data minimization: no raw audio or video persisted; Bedrock receives text and only in Clarity Mode;
  Privacy Mode sends nothing derived from audio.
- Logging: structured logs with an allowlist serializer; no PII, tokens, session credentials, transcript
  text, or request bodies.
- A written threat model and authorization test suite are required deliverables (task 26).

---

## 8. UI and UX

All screens meet WCAG 2.2 AA, support dynamic type to 200%, carry screen-reader labels, honor reduce-motion,
and contain **no em-dash or en-dash characters** in any string (NFR-10).

1. **Alert**: full-bleed thumbnail, event-specific haptic, single primary action, clear of watermark corners.
2. **Conversation (two-way)**: WebView video in the upper third, captions dominating below, per-turn labels,
   provisional and low-confidence styling, reply bar with at most 3 suggestions plus free text, "Speaking at
   your door" state.
3. **Conversation (Captions-Only)**: identical minus the reply bar; persistent banner "Replies unavailable on
   this device. You can still see what your visitor says."; one-tap "Open Ring app" action (FR-12.2, 12.3).
4. **History**: paginated, searchable, date-filterable; delete with confirmation.
5. **Settings**: mode switch with plain explanation that Privacy Mode keeps everything on the phone and does
   not use cloud suggestions; caption size and contrast within a 4.5:1 floor; per-pattern haptic toggles;
   strobe off by default; language selection; retention (90 days); "Delete all my data"; recording-notice
   text with the optional door-notice toggle; haptic pattern reference.
6. **First-run notice**: one-time recording-notice acknowledgement before first live use.
7. **Permission prompts**: in-context rationale before notifications and microphone. Camera never requested.
8. **Model download (Privacy Mode)**: explicit opt-in screen showing model size, never during a session.

Principle: fully usable with sound off and a screen reader on. No information conveyed by audio alone.

---

## 9. Testing strategy and acceptance criteria

- **Unit** (Dart and Node): services behind interfaces with fixtures. Cover unified auth recovery, webhook
  dedupe, probe logic, sticky-mode transitions, confidence styling for partial and final, ASR gating,
  pagination cursors.
- **Contract**: every route validated against its Fastify JSON schema; HMAC and idempotency; pagination
  contract; authorization rejection of foreign `residentSub`.
- **Integration**: end-to-end session against fixture Ring and fixture ASR; assert exactly one peer
  connection and the `sendrecv`/`recvonly` shape.
- **Probe and injection harness** (AT-5, AT-6): assert audio energy on the outbound track within 2 s; assert
  probe failure yields a session that is Captions-Only throughout.
- **Echo suppression** (AT-18): inject TTS, assert the inbound return is not transcribed and the gate
  reopens within 300 ms.
- **Privacy assertion** (AT-8): network capture proves zero audio and zero transcript-text egress; filesystem
  proves no audio or video artifacts.
- **Accessibility** (AT-9): automated scan plus manual TalkBack and VoiceOver pass on every screen; contrast
  floor enforced; zero AA violations gates the build.
- **Degradation matrix** (AT-20, NFR-5): for each dependency (Bedrock, Transcribe, push, visual processor,
  backend) assert the defined degraded behavior and that no session crashes.
- **Latency harness** (NFR-1): automated measurement of G1a, G1b, G2, G3 on reference devices; regression
  fails CI.
- **Captions-Only regression** (AT-10): the full suite passes with `outboundAvailable = false`.
- **UI copy lint** (AT-24): CI fails on an em-dash or en-dash in any UI string resource.
- **Coverage gate**: at least 80 percent line coverage on domain services; every FR maps to at least one
  test (requirements §6).

---

## 10. Observability

- Structured JSON logs (pino on the backend) with correlation id equal to the Ring `requestId` where
  present; allowlist serializer enforces redaction.
- Metrics: G1a, G1b, G2, G3, probe success rate, Captions-Only session share, injection failure rate,
  Bedrock fallback rate, webhook acknowledgement time, refresh count, schema-validation failure count.
  CloudWatch on the backend plus an in-app debug overlay for the demo.
- Alarms: webhook acknowledgement over 5 s, Transcribe error rate, 429 rate, probe success rate falling
  below a threshold.

---

## 11. Deployment and environments

- **local**: fixtures only, no AWS, no real Ring. Fixture device loading lives here, not in the product
  requirements [R-8].
- **staging**: real AWS, Ring staging users (up to 10).
- **demo**: deterministic fixtures and cached golden ASR and Bedrock responses so a network or rate-limit
  hiccup cannot break the live demo. The outbound-audio path is always real, never mocked.
- **Backend**: containerized Fastify on AWS (App Runner or ECS Fargate), stateless, at least 2 instances,
  least-privilege IAM per service, KMS key for token encryption.
- **App**: iOS via TestFlight, Android internal track.
- **CI/CD**: lint, unit, contract, a11y, UI-copy, and latency gates on pull requests. CI configuration is
  never pushed directly to `main`. Deploy on merge after gates pass.

---

## 12. Known open items

None as of this revision. ARCH-1 and the §5.1 probe close the two previously blocking questions. Any new
ambiguity must be recorded here and in requirements §7 with a date and owner before code depends on it.
