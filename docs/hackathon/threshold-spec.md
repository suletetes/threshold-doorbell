# Threshold — Product & Engineering Specification

> **The first video doorbell experience built for the people who can't hear it.**
> Live on-device captions of what your visitor is actually saying, and a tap-to-speak reply sent back out
> through the doorbell — a complete two-way conversation with no hearing required.

Primary track: **Ring** · Mini-challenges entered: **AWS Builder** + **Open Source**
Platform: **Flutter (iOS + Android)** — mobile is intrinsic, not decorative (see §4).
Product name: **Threshold** — the audiology term for the quietest sound a person can detect, and the place
where a visitor stands. Both meanings are the product.
Repository: **`threshold-doorbell`** (`github.com/suletetes/threshold-doorbell`).
Open-source package (Open Source mini-challenge): **`flutter_ring_captions`**.

---

## 1. Problem statement & target users

**Primary persona — Priya, 34, profoundly deaf, lives alone.**
Priya already owns a Ring doorbell. It works exactly as designed: she gets a phone alert and sees a man
standing at her door. Then the interaction dies. He is saying something — which flat, whether she wants it
left next door, whether he needs a signature — and she has no access to any of it. Her options are ignore
the door, or open it to a stranger and mime. Her doorbell tells her *someone* is there. It has never once
told her *what they want*.

**Secondary persona — Bernard, 78, age-related hearing loss.**
He can't follow the intercom, and he's a doorstep-scam target. Threshold gives him captions plus a safe
scripted reply without opening the door. This persona is why the project lands in Ring's **caretaking**
priority category as well as **accessibility** — WHO data indicates more than a quarter of people over 60
live with disabling hearing loss.

**The gap, evidenced.** The entire existing market for deaf doorbells solves *alerting*: strobes, flashing
lights, 100dB chimes, vibrating pagers. Not one solves the conversation. See
`research-and-scoring.md` §4 for sources. Threshold attacks the unserved half.

---

## 2. Value proposition & differentiation

Ring's WebRTC session negotiates audio as `sendrecv` — bidirectional — while the canonical sample uses only
the inbound video. Threshold is built on the channel everyone else leaves idle:

1. **Inbound:** visitor speech → streaming ASR → live captions on the phone.
2. **Outbound:** resident's chosen reply → speech synthesis → injected into the outbound WebRTC audio track
   → **spoken aloud at the door**.

Differentiation that survives a skeptical judge:

- **Not a chatbot.** There is no assistant persona and no open-ended chat. The AI does perception
  (speech→text), synthesis (text→speech), and at most a three-option reply suggestion. The product is an
  assistive communication bridge, not a conversational wrapper over an API.
- **Privacy is architectural, not marketing.** Privacy Mode runs the entire speech pipeline on the handset
  via whisper.cpp. Doorstep audio never leaves the device. This is a real, checkable claim.
- **A novel artifact:** a searchable transcript of what people said at your door. Nothing on the market
  produces this.
- **Idiomatic depth:** implements Ring's own `VideoProcessor` plugin interface for visual context, so the
  integration reads as native to the ecosystem rather than bolted on.

---

## 3. User journeys

**Happy path.**
1. `person_detected` webhook fires → backend fans out to the app → phone plays a **distinct haptic pattern**
   (deaf users cannot rely on a chime) and shows the webhook's `thumbnail_url` full-bleed.
2. Priya taps **Open** → WebRTC session starts; audio `sendrecv`, video `recvonly`.
3. Visitor speaks → captions stream in with ~sub-second partials, large and high-contrast, styled by
   confidence so uncertain words are visibly uncertain rather than silently wrong.
4. Three contextual Smart Replies appear alongside a free-text field.
5. She taps *"Please leave it at the door."* → on-device TTS → sent up the outbound audio track → the
   visitor hears it from the doorbell → he answers → captions continue.
6. Conversation is saved as text, searchable later.

**Edge cases and how the product behaves.**

| Case | Behaviour |
|---|---|
| Visitor silent / no speech | Captions show an explicit "no speech detected" state; visual-context processor still reports "one person, holding a package" |
| Very noisy street | Silero VAD gates input; low-confidence words render dimmed; user can switch to Clarity Mode mid-call |
| ASR mishears | Confidence styling + free-text override; never present a guess as certain |
| Network drop mid-call | Privacy Mode keeps captioning locally; reconnect banner, session resume |
| Token expiry (OAuth) | Silent refresh via refresh token; if refresh fails, single re-auth prompt, conversation preserved |
| Privacy zones configured | Honour them; never process masked regions |
| Multiple visitors | Turn segmentation by speaker change; UI labels turns rather than merging them |
| Non-English speaker | Language selector; translation is an explicit nice-to-have, not core |

---

## 4. Why mobile is intrinsic

The Design criterion asks whether the interaction model is well-considered for the platform. For this user
the answer is only ever a phone: the alert must be **haptic** and on the body; captions must be readable
where the user actually is; replies must be one-thumb fast while a stranger waits. A desktop dashboard
cannot buzz in a pocket. Mobile is a requirement of the problem, not a preference.

Non-obvious use of the handset:
- **A haptic vocabulary** — distinguishable vibration patterns for person-at-door, motion, and
  conversation-started. The phone becomes the doorbell.
- **Screen strobe + torch** as a free software replacement for the flashing-light hardware this market sells.
- **Wearable relay** for wrist haptics.
- **Screen-reader and large-text integrity** to WCAG 2.2 AA — which Ring's own partner UX guide mandates.

---

## 5. Feature set, prioritised

**Must-have (the demo dies without these)**
1. OAuth 2.0 account linking + token refresh.
2. Webhook receiver (200 within 5s, idempotent on `request_id`) → push to device.
3. Haptic + visual visitor alert using `thumbnail_url`.
4. Live WebRTC session with bidirectional audio.
5. Streaming captions of visitor speech.
6. Tap-to-speak reply audible at the door.

**Should-have**
7. Privacy Mode (on-device) ↔ Clarity Mode (Transcribe) toggle.
8. Bedrock-generated contextual Smart Replies.
9. Saved, searchable conversation transcripts.
10. Custom `VideoProcessor` for visual context (person count, package/uniform cues).

**Nice-to-have — cut without hesitation**
11. Live translation. 12. Sign-language gesture replies via MediaPipe Hands. 13. Fire TV companion alert.

---

## 6. Technical architecture

Rendered diagrams (source in `diagrams/`, see `diagrams/README.md`):

![System overview](diagrams/01-system-overview.svg)

![Inbound caption flow](diagrams/02-inbound-caption-flow.svg)

![Outbound reply flow (ARCH-1)](diagrams/03-outbound-reply-flow.svg)

![Event and alert flow](diagrams/04-alert-event-flow.svg)

![Data and privacy model](diagrams/05-data-privacy-model.svg)

The text sketch below is kept as a quick reference.

```
Ring device
   │  WebRTC / WHEP  (audio sendrecv · video recvonly)
   ▼
Flutter app (iOS + Android)
   ├── flutter_webrtc ............. session, SDP exchange mirroring the sample's useWebRTCStream.ts
   ├── whisper_ggml / FFI→whisper.cpp  Privacy Mode: on-device Whisper + VAD, fully offline
   │                                (see R7 — rougher in Flutter than whisper.rn; Clarity Mode is default)
   ├── flutter_tts ................ reply synthesis → outbound audio track (see R1)
   ├── VideoProcessor port ........ reimplement Ring's plugin contract in Dart; google_mlkit / tflite_flutter
   └── haptics / a11y ............. haptic vocabulary, WCAG 2.2 AA, TalkBack/VoiceOver
        ▲                    │
        │ push (FCM/APNs/WS) │ audio frames (Clarity Mode only)
        ▼                    ▼
Backend (Dart shelf / or Node — framework-independent, talks HTTP+WS)
   ├── OAuth token exchange + refresh        ├── Amazon Transcribe streaming (partial results
   ├── Webhook receiver → fan-out            │   stabilization) — Clarity Mode, default
   └── Bedrock: Smart Replies from transcript└── conversation persistence
```

> **Framework note.** The app is Flutter/Dart. Everything below the dashed line (Ring OAuth/webhooks, AWS
> Transcribe, Bedrock) is plain HTTP/WebSocket and is framework-independent — it can stay Node or move to a
> Dart `shelf` server, your call. The only Flutter-specific cost is the on-device speech path (R7); the
> cloud path (Transcribe) is identical to any stack.

**Data model**

```ts
Device       { id, name, capabilities, privacyZones }
DoorEvent    { id, type: 'motion_detected'|'person_detected', ts, deviceId,
               confidence, boundingBox, thumbnailUrl, requestId }
Conversation { id, deviceId, startedAt, endedAt, turns: Turn[] }
Turn         { speaker: 'visitor'|'resident', text, confidence, ts,
               source: 'ondevice'|'transcribe'|'template' }
ReplyTemplate{ id, text, category, usageCount }
```

**AI components and where they run**

| Component | Location | Justification |
|---|---|---|
| Streaming ASR | **Transcribe (default)** *or* on-device whisper.cpp | Cloud is the reliable path in Flutter; on-device is the privacy stretch goal (R7) |
| VAD | On-device | Gates noise cheaply before inference |
| TTS | On-device (`flutter_tts`) | Latency; a stranger is waiting |
| Smart Replies | Bedrock | Short, non-latency-critical; satisfies AWS Builder |
| Visual context | On-device (`google_mlkit` / `tflite_flutter`) | Frames should not leave the phone |

**Ring-specific constraints honoured:** 100 req/s rate limit with exponential backoff; webhook idempotency;
privacy zones respected; overlays positioned to avoid the mandatory watermark in the top corners.

---

## 7. UI/UX principles & key screens

Principles: captions are the primary interface, not a secondary label; never present a guess as certain;
one-thumb replies; the app must be fully usable with sound off and screen reader on; calm — one meaningful
alert, not a firehose.

1. **Alert** — full-bleed visitor thumbnail, distinct haptic, single primary action.
2. **Conversation** — video top third, captions dominating the rest at adjustable size/contrast, turn
   labels, confidence styling.
3. **Reply bar** — three Smart Replies + free text; sending state shows "speaking at your door…".
4. **Transcript history** — searchable list of past door conversations.
5. **Settings** — Privacy/Clarity toggle, caption typography, haptic patterns, language, zones.

---

## 8. Rubric mapping & success metrics

| Criterion | How Threshold scores |
|---|---|
| **Tech Implementation** | Uses bidirectional WebRTC audio (the capability nobody else touches), `person_detected` webhooks with bbox/thumbnail, OAuth refresh, rate-limit handling, Ring's own `VideoProcessor` interface, on-device whisper.cpp, Transcribe streaming, Bedrock |
| **Design** | Purpose-built accessible mobile UX; WCAG 2.2 AA as required by Ring's partner UX guide; haptic vocabulary; coherent single-purpose product |
| **Potential Impact** | ~430M people with disabling hearing loss; >25% of over-60s; ~80% in low/middle-income countries where a free app beats specialist hardware; clear route to the Ring App Store |
| **Quality of Idea** | Converts an audio-first device into an accessible two-way text device for the users it currently excludes, using an idle channel in the sponsor's own stack |

Demo-day metrics to be able to state: caption latency (target <1s partials), on-device word error rate on
the demo script, end-to-end time from doorbell to first caption, % of demo runs completing without fallback.

---

## 9. Risks & scope control

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | **Injecting synthesised audio into the outbound WebRTC track in Flutter** — the single hardest unknown | Critical | **Spike this first, days 4–7, before anything else.** In `flutter_webrtc`, feed generated PCM into a custom audio track. Fallbacks in order: (a) run the media/audio pipeline in an in-app WebView (`webview_flutter`) where `AudioContext` → `MediaStreamTrack` injection is well-trodden; (b) platform channel to a thin native module that pushes PCM into the peer connection; (c) degraded demo: TTS through phone speaker. Never mock the feature judges came to see. |
| R2 | Ring Protection plan + real device needed for full testing | High | Budget on day 1; use the Playground token for API work meanwhile; register staging users early |
| R3 | On-device Whisper latency on mid-range Android | Medium | tiny/base quantised + VAD; **Clarity Mode (Transcribe) is the default**, so this only affects the privacy stretch goal |
| R4 | Watermark obscuring frames/overlays | Low | Keep overlays out of top corners |
| R5 | Scope creep into translation / sign language | Medium | Explicitly nice-to-have; feature freeze day 31 |
| R6 | Presenting ASR errors as fact in a safety context | Medium | Confidence-styled captions; never auto-act on a transcript |
| R7 | **On-device Whisper is less mature in Flutter than RN's `whisper.rn`** | Medium | Ship **Transcribe as the default caption engine**; treat on-device (`whisper_ggml` / FFI to `whisper.cpp`) as the privacy stretch goal. Demo still shows Privacy Mode if the spike lands; if not, the product is undamaged because Clarity Mode carries it |

---

## 10. Demo script (≤3 minutes, problem-first)

| Time | Beat |
|---|---|
| 0:00–0:45 | **Problem.** Priya. Show a real Ring alert: she can see him, she has no idea he's asking which flat. Then show the market — strobes, louder chimes — all solving the wrong half. "The doorbell tells her someone is there. It never tells her what they want." |
| 0:45–0:55 | **Trigger.** "Threshold is the other half." |
| 0:55–2:05 | **Aha, live.** Doorbell → phone buzzes with its distinct pattern → captions stream as a person speaks at the door → tap a Smart Reply → **the doorbell speaks it aloud** → visitor replies → captions continue. A complete two-way conversation, no hearing involved. Then flip **Privacy Mode** on and show it still captioning with the network cut. |
| 2:05–2:40 | **Depth.** One breath of architecture: Ring's `sendrecv` audio channel → Amazon Transcribe streaming (or on-device Whisper in Privacy Mode) → Bedrock smart replies, all in a Flutter app. Show the transcript log. Note WCAG 2.2 AA. |
| 2:40–3:00 | **Impact close.** 430M people with disabling hearing loss; a quarter of over-60s; 80% in low- and middle-income countries where a free app beats buying hardware. "Ring already reached their door. Threshold makes it speak their language." |

Lead with the aha inside 90 seconds — judges are not required to watch past 3:00.

---

## 11. 38-day execution plan

The champion skill's `timeline_planner.py` supports 12–72h events, so gates are derived by proportion
instead, preserving the skeleton-at-25% and lock-before-submit structure.

| Phase | Days | Gate |
|---|---|---|
| Scout & prep | 1–3 | Ring dev account, OAuth app registered, Protection plan active, Playground token, repo + MIT license visible, $150 AWS credits requested, sample running end-to-end |
| **Risk spike (R1)** | 4–7 | **Go/no-go:** synthesised audio provably audible at the door. If not → WebView pipeline, decided here, not later |
| **Skeleton (25% mark)** | 8–12 | Ugly but complete: webhook → push → live view → captions on screen → one canned reply spoken at the door |
| Core | 13–22 | Clarity Mode (Transcribe) captions, Smart Replies, haptic vocabulary, transcripts, Dart VideoProcessor; on-device Whisper as stretch |
| Polish & accessibility | 23–30 | WCAG 2.2 AA audit, screen reader, contrast, typography, onboarding, empty/error states |
| **Feature freeze** | 31 | No new features |
| Submission assets | 32–36 | Rehearse live demo ×5; record video twice; README as case study; **friction log** (up to 10% bonus); product feedback; OSS contribution |
| **Code lock** | 37 | Hardcode demo path, backup video ready |
| **Submit** | 38 (23 Oct) | Submit ≥12h early — not 30 minutes |

**Mini-challenge execution.** *AWS Builder:* Bedrock (Smart Replies) + Transcribe streaming (Clarity Mode),
documented in the feedback field. *Open Source:* publish the caption/reply bridge as a standalone MIT
Dart package (`flutter_ring_captions`) **and** open a PR to `AmazonAppDev/ring-api-helloworld` adding an
accessibility-oriented video processor — their `CONTRIBUTING.md` explicitly welcomes PRs (fork, focused
change, open an issue first for significant work), and a PR to the sponsor's own sample is maximally
visible to judges.

---

## 12. First implementation steps

```bash
# 1. Baseline: get the sanctioned sample running and confirm the API surface
git clone https://github.com/AmazonAppDev/ring-api-helloworld.git
cd ring-api-helloworld && npm install
cp .env.example .env.local          # paste Playground token (~30 min lifetime)
npm run dev                          # verify device list + WebRTC live view

# 2. Confirm the event surface from the terminal
cd scripts && pip install -r requirements.txt
python explore_apis.py --token "$RING_TOKEN"

# 3. Mobile app skeleton (Flutter)
flutter create threshold
cd threshold
flutter pub add flutter_webrtc flutter_tts vibration
flutter pub add google_mlkit_object_detection   # visual context (or tflite_flutter)
# on-device speech (stretch): flutter pub add whisper_ggml   # or FFI to whisper.cpp

# 4. THE SPIKE (do before any UI): prove outbound audio reaches the door
#    Minimal Flutter screen using flutter_webrtc: open a session with the audio
#    transceiver as sendrecv, push a synthesised PCM buffer into a custom
#    outbound audio track, and confirm it is audible at the device.
#    This is the go/no-go for the whole architecture. If flutter_webrtc can't
#    inject it directly, fall back to the webview_flutter audio pipeline HERE.
```

Then: webhook receiver with idempotency → push channel → captions → reply bar, in that order.
