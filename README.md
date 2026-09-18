# Threshold

**The first video doorbell experience built for the people who can't hear it.**

Live captions of what your visitor is saying, and a tap-to-speak reply spoken aloud out of the
doorbell: a complete two-way conversation, no hearing required.

Built for the **Amazon Developer Hackathon 2026** · **Ring** track · **Flutter** (iOS + Android)
Mini-challenges: **AWS Builder** (Amazon Transcribe + Bedrock) · **Open Source** (`flutter_ring_captions`)

> *threshold*: the audiology term for the quietest sound a person can detect, and the place where a
> visitor stands. Both meanings are the product.

---

## The problem

A deaf person's Ring doorbell tells them *someone* is at the door. It never tells them *what that person
is saying*. Every existing "deaf doorbell" product only solves the alert: brighter lights, louder chimes,
vibrating pagers. None handle the conversation. Threshold builds the missing half.

Roughly **430 million people** have disabling hearing loss (WHO); more than 1 in 4 people over 60. Threshold
is a free app on a doorbell they already own.

## How it works

```
Visitor speaks  →  Ring doorbell  →  phone  →  speech-to-text  →  live captions on screen
Resident taps a reply  →  text-to-speech  →  doorbell speaker  →  visitor hears it out loud
```

The insight: Ring's WebRTC audio channel is **bidirectional** (`sendrecv`), but Amazon's own sample uses
only the inbound half. Threshold is built on the channel everyone else leaves idle.

## Tech stack

| Concern | Technology |
|---|---|
| App (iOS + Android) | Flutter / Dart |
| Live session (video in, two-way audio) | WebView browser WebRTC (decision ARCH-1). Only the browser runtime can inject synthesized audio into the outbound track. |
| Captions, default (accuracy) | Amazon Transcribe streaming |
| Captions, Privacy Mode (on-device) | on-device Whisper (`whisper_ggml` / FFI to whisper.cpp, or WASM in the WebView) |
| Smart replies | Amazon Bedrock (Clarity Mode only; on-device suggestions in Privacy Mode) |
| Reply spoken at the door | `flutter_tts` injected via the WebView AudioContext pipeline |
| Distinct alert patterns | `vibration` (haptic vocabulary) |
| Visual context | `google_mlkit_object_detection`, privacy-zone aware, on-device only |
| Backend | Node 20 + Fastify (stateless): OAuth, webhooks, signaling broker, ASR relay, replies, transcripts |
| Ring integration | Ring Partner API (OAuth 2.0 + webhooks) |

### Architecture decision ARCH-1: one WebRTC stack, owned by the WebView

The live session runs inside an in-app WebView because only the browser runtime
can inject synthesized audio into an outbound track
(`AudioContext` to `MediaStreamAudioDestinationNode` to
`RTCRtpSender.replaceTrack`). `flutter_webrtc` cannot inject outbound audio on
any platform, and running it alongside the WebView would open two sessions to
one doorbell. So there is exactly one peer connection, audio `sendrecv`, video
`recvonly`, and Flutter draws captions and controls as overlays on top. See
`.kiro/specs/threshold-doorbell/design.md` for the full rationale.

## Repository layout

```
.
├── .kiro/                          # source of truth: specs + steering
│   ├── specs/threshold-doorbell/   # requirements.md, design.md, tasks.md
│   └── steering/                   # product.md, tech.md, structure.md
├── app/                            # Flutter application
│   └── lib/
│       ├── captions/               # confidence styling, turn segmentation,
│       │                           #   language selection, model provisioning,
│       │                           #   on-device ASR engine port
│       ├── reply/                  # sticky outbound mode, on-device suggestions
│       ├── alerts/                 # haptic vocabulary, strobe, push receiver
│       ├── connectivity/           # offline / backend-outage state machine
│       ├── vision/                 # privacy-zone geometry, presence cues
│       └── a11y/                   # UI-copy dash lint engine
├── backend/                        # Node 20 + Fastify (stateless)
│   ├── src/routes/                 # oauth, webhook, devices, events, signaling,
│   │                               #   asr, replies, transcripts
│   ├── src/services/               # ring, transcribe, bedrock, store (+ fixtures)
│   ├── src/observability/          # redacting logger, metrics
│   └── docs/                       # THREAT_MODEL, PRIVACY_POLICY, OPERATIONS
├── packages/
│   └── flutter_ring_captions/      # extracted MIT package (Open Source challenge)
├── docs/hackathon/                 # strategy, research, friction log
└── LICENSE                         # MIT
```

## Case study: building the missing half of the doorbell

Threshold is a study in taking one deliberate architectural bet and letting it
order everything else.

- **The bet (ARCH-1).** Amazon's Ring sample uses only the inbound half of a
  bidirectional WebRTC channel. Threshold's entire value is the outbound half: a
  synthesized reply audible at the door. That capability is only reachable
  through a browser WebRTC runtime, so the whole live session moved into a
  WebView. This decision was made first and de-risked with a spike before any UI
  was built.

- **Ports and adapters everywhere.** Every external dependency (Ring, Transcribe,
  Bedrock, push, the datastore, the on-device ASR engine, connectivity, vision,
  locale) sits behind an interface with a fixture. That is what lets the app and
  backend be developed and fully tested offline, and it is why the demo build can
  use deterministic golden responses while the outbound-audio path stays real.

- **Accessibility as a hard constraint, not a polish pass.** A firm rule that no
  em-dash or en-dash appears in any user-facing string is enforced by a CI lint
  gate and a reply-rendering sanitizer. Caption confidence is a semantic signal
  the UI maps to weight and label, never color or audio alone.

- **Privacy by construction.** No raw audio or video is ever persisted. Privacy
  Mode transcribes entirely on-device with zero egress, proven by fixtures that
  count transmitted bytes and keep them at zero. Ring tokens are KMS-encrypted on
  the backend and never touch the device.

The extracted, reusable heart of the caption and reply logic ships as a
standalone MIT package, [`flutter_ring_captions`](packages/flutter_ring_captions/README.md).

## Status

Under active implementation against `.kiro/specs/threshold-doorbell/tasks.md`.
The backend (OAuth with PKCE, KMS token store, webhook, devices and events,
signaling broker, ASR relay, transcripts, replies, observability) and the
device-independent app logic (captions, alerts, sticky outbound mode,
connectivity, language, model provisioning, vision) are implemented and covered
by fixture-based tests. Device-bound work (the live WebView session, real
permissions, the on-device latency and a11y device passes) is verified on a
developer machine with Ring credentials, not in CI.

## Getting started

App:

```bash
cd app
flutter pub get
flutter test          # the primary correctness gate
flutter run           # requires a device or emulator
```

Backend:

```bash
cd backend
npm ci
npm run typecheck && npm run lint && npm test
npm run dev           # local mode, fixtures only, no AWS or real Ring
```

Full device testing needs a Ring developer account, an OAuth app, and a Ring
Protection plan. See `docs/hackathon/threshold-spec.md` for the plan and
`.kiro/ENVIRONMENT.md` for the verified toolchain.

## License

[MIT](./LICENSE)
