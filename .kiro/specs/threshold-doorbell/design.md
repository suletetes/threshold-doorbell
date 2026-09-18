# Design — Threshold (threshold-doorbell)

Implementation-ready technical design. Every failure mode and edge case has defined behavior. No open
questions.

---

## 1. System architecture

```
┌──────────────┐   WebRTC (WHEP)   ┌───────────────────────────────────────────┐
│  Ring device │  audio sendrecv   │  Flutter app (iOS 14+ / Android 8+)         │
│  (doorbell)  │  video recvonly   │                                             │
└──────┬───────┘◄─────────────────►│  UI (Riverpod)                              │
       │ webhooks                  │   ├─ Alert · Conversation · ReplyBar        │
       │ (motion/person)           │   ├─ History · Settings                     │
       ▼                           │  Domain services (interfaces + fixtures)    │
┌──────────────────────────┐       │   ├─ RingClient        (REST + rate limit)  │
│  Backend (Node 20 +       │◄─────►│   ├─ SignalingClient   (session broker)     │
│  Fastify) — stateless     │  HTTPS│   ├─ CaptionEngine      Clarity | Privacy   │
│   ├─ /oauth/*             │  + WS │   ├─ ReplyAudioBridge   (WebView pipeline)  │
│   ├─ /webhook             │       │   ├─ SmartReplyService  (Bedrock)           │
│   ├─ /devices, /events    │       │   └─ HapticService                          │
│   ├─ /signaling (WS)      │       └───────────────┬─────────────────────────────┘
│   └─ /transcripts         │                       │ on-device only
│  AWS: Transcribe stream,  │                       ▼
│  Bedrock, Secrets Mgr,    │             Whisper (Privacy Mode) · google_mlkit
│  DynamoDB                 │
└──────────────────────────┘
```

**Trust boundary:** the mobile app never holds the Ring client secret or AWS credentials. All privileged
calls (OAuth exchange/refresh, Transcribe, Bedrock) go through the backend. Privacy Mode is the exception:
ASR runs fully on device and touches no backend.

**Statelessness:** the backend keeps no per-request state in memory. OAuth tokens, event dedupe keys, and
transcripts live in DynamoDB (or the fixture store in local/demo). This satisfies NFR-6.

---

## 2. Technology decisions (with justification)

| Layer | Choice | Version (pin; verify latest at build) | Why |
|---|---|---|---|
| App | Flutter / Dart | Flutter ≥ 3.24, Dart ≥ 3.4 | Single codebase iOS+Android; mobile is intrinsic to the problem. |
| State | `flutter_riverpod` | ^2.6.0 | Compile-safe DI, testable, no BuildContext coupling; fixtures injectable. |
| WebRTC (inbound) | `flutter_webrtc` | ^0.12.0 | Only mature RN-parity WebRTC for Flutter; handles inbound video/audio + SDP. |
| **Outbound audio** | **WebView pipeline** (`webview_flutter` ^4.7 + JS AudioContext) | — | **flutter_webrtc lacks Insertable Streams on all platforms (verified pub.dev/repo). The browser inside a WebView supports AudioContext → MediaStreamTrack injection, which is the proven path.** Native platform-channel PCM is the only approved alternative. |
| TTS | `flutter_tts` | ^4.2.0 | `synthesizeToFile` produces WAV/PCM to feed the bridge; on-device, low latency. |
| Cloud ASR | Amazon Transcribe streaming (WebSocket, partial-results stabilization) | current | Purpose-built for live captions; anchors AWS Builder mini-challenge. |
| On-device ASR | whisper.cpp via `whisper_ggml` / FFI | current | Privacy Mode; tiny/base quantized + VAD. Stretch — Clarity Mode is default. |
| Smart replies | Amazon Bedrock (Claude/Titan text) | current | Short suggestions; non-latency-critical; AWS Builder. |
| Vision context | `google_mlkit_object_detection` | ^0.14.0 | On-device person/object cues; frames never leave phone. |
| Haptics | `vibration` | ^2.0.0 | Distinct patterns per event. |
| Push | `firebase_messaging` (FCM, APNs via FCM) | ^15.x | Cross-platform push for alerts. |
| Backend | Node 20 LTS + Fastify | Fastify ^4.28 | Fast, schema-validated routes, first-class JSON-schema validation; AWS SDK v3. |
| AWS SDK | `@aws-sdk/*` v3 | ^3.x | Transcribe streaming + Bedrock + Secrets Manager + DynamoDB. |
| Store | DynamoDB (prod) / in-memory fixture (local/demo) | — | Stateless backend; single-digit-ms lookups for dedupe + transcripts. |
| Secrets | AWS Secrets Manager | — | Ring client secret + HMAC key + AWS creds; never in app or logs. |

**Rejected:** flutter_webrtc raw track injection (Insertable Streams unsupported); persisting audio (privacy
non-goal N6); a bespoke auth system (Ring OAuth is the identity).

---

## 3. Data models & schema

TypeScript shapes (backend authoritative; Dart mirrors them).

```ts
type DeviceId = string;      // Ring device id
type EventType = 'motion_detected' | 'person_detected';
type Speaker = 'visitor' | 'resident';
type TurnSource = 'transcribe' | 'ondevice' | 'template' | 'freetext';
type CaptionMode = 'clarity' | 'privacy';

interface Device {
  id: DeviceId;
  name: string;
  capabilities: string[];          // e.g. ['live_view','motion','person']
  privacyZones: BoundingBox[];
  cachedAt: string;                // ISO8601; TTL 24h
}

interface BoundingBox { x: number; y: number; width: number; height: number; }

interface DoorEvent {
  eventId: string;                 // stable id
  requestId: string;               // idempotency key (unique index)
  type: EventType;
  deviceId: DeviceId;
  timestamp: string;               // ISO8601
  confidence: number | null;       // 0..1
  boundingBox: BoundingBox | null;
  thumbnailUrl: string | null;
  processedAt: string | null;      // set once; null until first processing
}

interface Turn {
  turnId: string;
  speaker: Speaker;
  text: string;
  confidence: number | null;       // per-turn min token confidence
  timestamp: string;
  source: TurnSource;
}

interface Conversation {
  conversationId: string;
  deviceId: DeviceId;
  residentSub: string;             // Ring account subject (owner)
  startedAt: string;
  endedAt: string | null;
  mode: CaptionMode;
  turns: Turn[];
}

interface OAuthTokens {            // backend/secure store only — never returned to app
  residentSub: string;
  accessToken: string;
  refreshToken: string;
  expiresAt: string;
}
```

**DynamoDB tables (prod):**
- `events` — PK `requestId` (conditional put enforces idempotency), TTL 7 days.
- `conversations` — PK `residentSub`, SK `conversationId`; GSI on `startedAt` for date filtering.
- Tokens live in Secrets Manager keyed by `residentSub`, not DynamoDB.

---

## 4. API contracts (backend)

All requests/responses JSON. All 4xx/5xx use the error envelope:
`{ "error": { "code": string, "message": string, "requestId": string } }`.

| Method | Path | Auth | Request | Success | Errors |
|---|---|---|---|---|---|
| GET | `/oauth/start` | none | `?deviceHint` | 302 → Ring authorize (with PKCE+state) | 500 `oauth_init_failed` |
| GET | `/oauth/callback` | none | `?code&state` | 302 → app deep link with session cookie | 400 `state_mismatch`, 400 `code_exchange_failed` |
| POST | `/oauth/refresh` | session | `{}` | 200 `{ expiresAt }` | 401 `refresh_failed` |
| GET | `/devices` | session | — | 200 `Device[]` | 401, 429 `rate_limited`, 502 `ring_unavailable` |
| GET | `/events?since` | session | — | 200 `DoorEvent[]` | 401, 429, 502 |
| POST | `/webhook` | HMAC | Ring payload | 200 `{ ok: true }` (≤5 s) | 401 `bad_signature`, 200 on duplicate (idempotent) |
| GET | `/signaling` (WS) | session | WHEP offer msgs | WS: `{ sdpAnswer, sessionUrl }` | close 4401 unauth, 4408 timeout |
| POST | `/asr/stream` (WS) | session | PCM frames (Clarity) | WS: `{ partial|final, tokens[] }` | close 4401, 4500 `transcribe_error` |
| POST | `/replies` | session | `{ conversationId, contextText }` | 200 `{ suggestions: string[≤3] }` | 200 fixed set on Bedrock error |
| GET | `/transcripts?query&from&to` | session | — | 200 `Conversation[]` (turns text only) | 401 |
| POST | `/transcripts` | session | `Conversation` | 201 `{ conversationId }` | 401, 400 `schema` |
| DELETE | `/transcripts/:id` | session | — | 204 | 401, 404 |

**Webhook contract detail:** verify HMAC over the raw body using the Secrets-Manager key; compute in constant
time; on mismatch return 401 without processing. On valid: conditional-put by `requestId`; if the item
already exists, return 200 immediately (dedupe). Then enqueue push. Must complete ≤ 5 s (offload push to an
async worker if needed; still ack 200 first).

---

## 5. State machines

**Session lifecycle:**
```
IDLE ──open──► CONNECTING ──ice ok──► LIVE ──end/bg>30s──► CLOSING ──► IDLE
   ▲               │ fail×2                │ net drop            │
   └───────────────┘ (show error)         ▼                     │
                                    RECONNECTING ──ok──► LIVE    │
                                          │ fail×2 ──► CLOSING ──┘
```
- Privacy Mode: on `net drop`, captions continue locally; RECONNECTING affects only outbound reply + video.

**Reply lifecycle:**
```
COMPOSING ──send──► SYNTHESIZING ──audio ready──► SPEAKING_AT_DOOR ──done──► SENT(logged)
                         │ tts fail                    │ inject fail
                         ▼                             ▼
                    ERROR(retry once)         DEGRADE→Captions-Only + notice
```

**Caption mode:** `clarity ⇄ privacy` toggled only between sessions; mid-session toggle is queued and
applied on next session with a visible indicator (FR-10.1).

---

## 6. Error handling & edge cases (exhaustive)

| Condition | Behavior |
|---|---|
| OAuth state mismatch | Reject, message FR-1.3, no token stored. |
| Access token expired | Refresh once, retry once; on refresh fail → FR-1.5 preserve+reprompt. |
| Ring 429 | Token-bucket + backoff w/ jitter; never exceed 100 rps. |
| Ring 5xx | Retry ≤2 w/ backoff; then `ring_unavailable`, cached devices shown read-only. |
| Duplicate webhook | Idempotent 200, processed once (FR-3.2). |
| Bad webhook signature | 401, dropped, logged without payload body. |
| Webhook slow downstream | Ack 200 first, push async (FR-3.1). |
| Push fails/disabled | Foreground poll `/events?since` (FR-3.5). |
| ICE/connect fail | Retry ≤2, then session error (FR-4.4). |
| App backgrounded >30 s | Close session, release session URL (FR-4.3). |
| No speech ≥5 s | Explicit "No speech detected" (FR-5.4). |
| Low-confidence tokens | De-emphasized styling (<0.6), never certain (FR-5.3). |
| Transcribe WS drop | Auto-reconnect; buffered audio ≤2 s replayed; else prompt Privacy Mode. |
| Bedrock timeout/error | Fixed safe replies within 2 s (FR-7.3). |
| **Outbound injection unavailable** | Enter Captions-Only Mode + notice (FR-6.4/FR-12); no silent fail. |
| Privacy zones present | No processing/display of masked regions (FR-11). |
| Multiple visitors | New labeled turn per speaker change (FR-5.5). |
| Non-English speech | Language selector; default en-*; translation out of scope. |
| Watermark overlap | Overlays kept out of top corners (FR-4.5). |
| Transcript delete | Device+backend removed atomically, confirmed (FR-8.4). |

---

## 7. Security & auth model

- OAuth 2.0 authorization-code + PKCE; `state` CSRF check; secret exchange server-side only (FR-1).
- Session between app and backend via HttpOnly, Secure, SameSite=strict cookie or signed bearer; 30-min
  idle expiry; bound to `residentSub`.
- Tokens: Secrets Manager (backend) + Keychain/Keystore (device). Never logged, never in shared prefs.
- Webhooks: HMAC constant-time verification; reject on mismatch.
- Transport: TLS 1.2+ everywhere; WSS for signaling/ASR.
- Data minimization: no raw audio/video persisted (N6); only text; Bedrock/Transcribe receive only what
  each strictly needs; Privacy Mode sends nothing.
- Logging: structured logs exclude PII, tokens, transcript text, and payload bodies.

---

## 8. UI/UX requirements

Screens (all WCAG 2.2 AA, dynamic type to 200%, screen-reader labeled, reduce-motion honored):
1. **Alert** — full-bleed thumbnail, event-specific haptic, one primary action ("Open"), out of watermark corners.
2. **Conversation** — video top third; captions dominate; per-turn labels; confidence styling; large,
   high-contrast, user-scalable text.
3. **Reply bar** — ≤3 Smart Replies + free-text; "Speaking at your door…" state; duplicate-send disabled.
4. **History** — searchable/date-filterable transcript list; delete with confirm.
5. **Settings** — Privacy/Clarity toggle (with active-session indicator), caption size/contrast live preview,
   per-pattern haptic toggles, strobe/torch toggle.
Principle: fully usable with sound off + screen reader on. No information by audio alone.

---

## 9. Testing strategy & acceptance criteria

- **Unit** (Dart + Node): services behind interfaces; fixtures for Ring/AWS. Cover token refresh, dedupe,
  confidence styling logic, reply state machine.
- **Contract**: backend routes validated against JSON schemas (Fastify schemas); webhook HMAC + idempotency.
- **Integration**: end-to-end session against fixture Ring + fixture ASR; verify SDP `sendrecv`/`recvonly`.
- **Spike harness (AT-5)**: automated check that injected TTS audio produces measurable energy on the
  outbound track within 2 s.
- **Privacy assertion (AT-8/NFR-4)**: network capture during a Privacy-Mode session asserts zero audio
  egress; filesystem assert no audio/video artifacts.
- **Accessibility (AT-9/NFR-2)**: automated a11y scan per screen + manual TalkBack/VoiceOver pass; zero AA
  violations gate the build.
- **Degrade regression (AT-10/FR-12)**: full suite passes with outbound injection disabled.
- **Coverage gate**: ≥ 80% line coverage on domain services; 100% of FRs mapped to at least one test (see
  requirements §6 traceability).

---

## 10. Observability & logging

- Structured JSON logs (pino on backend, `logger` package on app) with correlation id = Ring `requestId`
  where present; PII/token/transcript-text redaction enforced by a serializer allowlist.
- Metrics: caption-first latency (G1), partial latency (G2), tap→audio latency (G3), session success rate,
  Bedrock fallback rate, webhook ack time, refresh count. Exposed via CloudWatch (backend) and an in-app
  debug overlay for the demo.
- Alarming (prod): webhook ack > 5 s, Transcribe error rate, 429 rate.

---

## 11. Deployment & environments

- **Environments:** `local` (fixtures, no AWS), `staging` (Ring staging users ≤10, real AWS), `demo`
  (deterministic fixtures + cached golden responses for the recorded/live demo).
- **Backend:** containerized Fastify on AWS (App Runner or ECS Fargate), stateless, ≥2 instances; secrets
  via Secrets Manager; DynamoDB; least-privilege IAM per AWS service.
- **App:** Flutter build for iOS (TestFlight/staging) and Android (internal track).
- **CI/CD:** lint + unit + contract + a11y gates on PR; never push CI config directly to `main`; deploy on
  merge to `main` after gates pass.
- **Demo safety:** fixture device + cached ASR/Bedrock responses so a network or rate-limit hiccup never
  breaks the live demo; the outbound-audio path is real, never mocked.

---

## 12. Open questions

None. All ambiguities resolved above.
