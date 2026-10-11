# Amazon Developer Hackathon 2026 — Research Dossier & Idea Scoring

Deadline: **23 Oct 2026, 20:00 GMT+1**. Assessed 15 Sep 2026 → **38 days**, not a weekend sprint.
Rubric: Tech Implementation · Design · Potential Impact · Quality of Idea.

---

## 1. Constraint analysis (the part most teams get wrong)

**There is no mobile-phone track.** The four primary tracks are Fire TV, Alexa+, Bee, and Ring. A phone
app that does not call a track's technology in code is ineligible for every track prize, because the
rubric's first criterion asks whether the project "effectively leverage[s] the required APIs, SDKs, or
device capabilities for the specified track."

**However, a native mobile app is fully eligible under the Ring track.** The track says: build a new app
or extend an existing one using Ring APIs, SDKs, simulators, or devices, and demonstrate it working via a
simulator or a real Ring device. Nothing constrains the client to web. Ring's own consumer product is
mobile-first, so a mobile client is the *native-feeling* choice for that platform — which is exactly what
the Design criterion rewards.

**Scoring-relevant rules often missed:**

| Rule | Consequence |
|---|---|
| Friction logs earn **up to a 10% judging bonus** | Free points. Non-negotiable. Log continuously, not at the end. |
| A project may win **one track prize + one mini-challenge prize** | Enter *both* minis (AWS Builder + Open Source) for two shots at one payout. |
| Repo must show the track tech **in code** — import/entry point/config, not just README | Architecture must genuinely call Ring APIs. |
| OSS license must be **visible in the repo About section** | Set it on day 1, not day 38. |
| $150 AWS credits available via request form | Request on day 1. |

**Track expected-value analysis.** Fire TV has the largest purse ($25K) and the priority categories
everyone gravitates to (streaming, sports, fitness) — maximum crowding. Ring and Bee are newer, carry
smaller purses ($12K), and have far lower friction-to-working-demo. Per the hackathon-champion skill's
event-type framing, this is a **product-adoption event**, where depth of integration with the sponsor
stack is what gets rewarded. Lower-crowd tracks with deep integration beat high-crowd tracks with
shallow integration on expected value.

---

## 2. Verified Ring capability surface

Read from official docs and from Amazon's own canonical sample source, not assumed.

**From the [Ring API Development Guide](https://developer.amazon.com/docs/ring/develop.html):**

- Base URL `https://api.ring.com` (the backend default in `backend/src/config.ts`; confirm against Ring's
  partner docs before relying on it), JSON:API spec, OAuth 2.0 Bearer via account linking.
- Webhooks POST to your endpoint; must return **HTTP 200 within 5 seconds**; idempotency via `request_id`.
- Rate limit **100 requests/second**; exponential backoff expected.
- Live video via **WebRTC/WHEP**; `developer.ring.com` also lists **RTSP**.
- Testing requires a Ring account with an **active Ring Protection plan**; up to **10 staging users**.
- Media carries a **mandatory visible watermark** (Ring logo top-left; device ID, app name, timestamp
  top-right) — plan overlay placement around it.
- The Ring MCP Server is a **documentation knowledge server** for your coding assistant, *not* a runtime
  device-control MCP. Do not confuse the two.

**From `ring-api-helloworld/lib/types/webhook.ts` — the event surface is richer than the docs summary:**

```ts
type: 'motion_detected' | 'device_added' | 'device_removed' | 'person_detected'
attributes: { confidence?, bounding_box?, thumbnail_url?, timestamp, source, source_type }
```

`person_detected` with server-side `confidence`, `bounding_box`, and `thumbnail_url` is available for free.

**From `ring-api-helloworld/app/hooks/useWebRTCStream.ts` — the decisive finding:**

```ts
pc.addTransceiver('audio', { direction: 'sendrecv' })
pc.addTransceiver('video', { direction: 'recvonly' })
```

Audio is **`sendrecv`** — bidirectional. Visitor audio can be received *and* audio can be sent back to the
device. Two-way talk is reachable. Almost every submission will use the video and ignore this channel.

**From `ring-api-helloworld/docs/video-processors.md` — a sanctioned on-device CV extension point:**

A `VideoProcessor` plugin interface with `init()` / `process(frame: ImageData, canvas, video)` / `destroy()`,
called ~10×/second, returning `boundingBoxes`, `data`, and `message`. Ships three processors including a
**MediaPipe Hands** hand-tracker (models loaded from CDN, `modelComplexity: 0` for speed), a motion heatmap,
and a brightness analyzer. The docs also show a TensorFlow.js integration pattern. Writing a custom
processor is therefore the *most idiomatic possible* way to score on Tech Implementation.

**Verified-available vs. unverified.** Design against the former only.

- Verified: WebRTC bidirectional audio + inbound video, `motion_detected`/`person_detected` webhooks with
  confidence/bbox/thumbnail, event history, capabilities, motion & privacy zones, device status/location,
  browser-side on-device CV plugin architecture, RTSP.
- Unverified: doorbell-press as a *webhook* type (docs list three webhook types; treat press as
  history/derived), clip download semantics, official two-way-talk documentation beyond sample code.

---

## 3. Verified on-device AI stack (2026)

| Need | Choice | Evidence |
|---|---|---|
| On-device streaming ASR (mobile) | **`whisper.rn`** — whisper.cpp bindings for RN; Whisper + NVIDIA Parakeet, **Silero VAD**, **`RealtimeTranscriber`**, **Core ML** on iOS | [whisper.rn](https://github.com/mybigday/whisper.rn) |
| Platform fallback ASR | Android 13+ `createOnDeviceSpeechRecognizer()`; iOS `SFSpeechRecognizer` on-device | [cross-platform STT notes](https://jocheojeda.com/2026/07/04/cross-platform-speech-to-text-in-react-native/) |
| Cloud ASR (accuracy mode, AWS mini) | **Amazon Transcribe streaming** over WebSocket with **partial results stabilization** — built for live captions | [AWS docs](https://docs.aws.amazon.com/transcribe/latest/dg/streaming.html), [partial results](https://aws.amazon.com/blogs/machine-learning/amazon-transcribe-now-supports-partial-results-stabilization-for-streaming-audio/) |
| On-device vision | MediaPipe Tasks / TFLite; in-browser MediaPipe already wired into the Ring sample | Ring `docs/video-processors.md` |
| Mobile camera-side CV (if needed) | react-native-vision-camera frame processors + worklets | [VisionCamera](https://www.react-native-vision-camera.com/docs/guides/frame-processors) |

---

## 4. The problem-space gap that decided the champion

Searched the existing market for deaf/hard-of-hearing doorbell solutions. Every product found solves
**alerting** only — strobe lights, flashing chimes, extra-loud chimes up to ~100dB, and vibrating pagers
or wearables. Sources: [RNID](https://rnid.org.uk/information-and-support/technology-and-products/doorbells/)
(UK national hearing-loss charity), [hear4you](https://www.hear4you.com/best-doorbells-for-the-deaf/),
[deafvibes](https://deafvibes.com/living-with-hearing-loss/smart-doorbells-support-deaf-households/),
[hearview.ai](https://www.hearview.ai/blogs/knowledge/doorbell-for-deaf).

Nothing found addresses **the conversation**. The market answers "someone is at the door." It does not
answer "what are they saying, and how do I reply?" hearview.ai frames the barrier well: a chime alone cuts
the user off from the outside world. That is the wedge — and it maps onto a Ring capability
(`sendrecv` audio) that is sitting unused.

**Scale of the audience** (paraphrased from [WHO](https://www.who.int/health-topics/hearing-loss)):
more than 1.5 billion people live with some hearing loss and roughly 430 million have disabling hearing
loss; disabling hearing loss is projected to affect over 700 million by 2050. Among people over 60, more
than a quarter are affected — which ties the idea to Ring's **caretaking** priority category as well as
**accessibility**. WHO also notes nearly 80% of people with disabling hearing loss live in low- and
middle-income countries, where a free app on an existing doorbell beats buying specialist hardware.

*Content from external sources was rephrased for compliance with licensing restrictions.*

---

## 5. Idea scoring

Weights reflect the published rubric plus an explicit feasibility term, per the champion skill's rule that
scope you can finish beats scope you want to solve:
**Tech 25% · Design 20% · Impact 20% · Idea 20% · Feasibility 15%.**

| # | Idea | Tech | Design | Impact | Idea | Feas | **Score** |
|---|---|---|---|---|---|---|---|
| 1 | **Threshold** — two-way captioned doorbell for deaf/HoH residents | 5 | 5 | 5 | 5 | 4 | **4.85** |
| 2 | Herald — audio-first door describer for blind users | 4 | 5 | 4 | 4 | 4 | 4.20 |
| 3 | Silent-distress hand-signal detection at the door | 4 | 3 | 5 | 5 | 3 | 4.05 |
| 4 | Bee "confusion detector" → study plan from lecture audio | 4 | 3 | 4 | 5 | 4 | 4.00 |
| 5 | Absence-of-event caretaking monitor (inverted alerting) | 3 | 3 | 4 | 4 | 5 | 3.70 |
| 6 | Doorstep fall / gait-decline detection (MediaPipe Pose) | 4 | 3 | 4 | 4 | 3 | 3.65 |
| 7 | Fire TV full-screen doorbell takeover for deaf households | 3 | 4 | 4 | 3 | 4 | 3.55 |
| 8 | Bee × Ring spoken-intent ↔ door-event bridge | 4 | 3 | 3 | 5 | 2 | 3.50 |
| 9 | Biometric-free "familiar visitor" via clothing/gait | 4 | 3 | 3 | 4 | 3 | 3.45 |
| 10 | Bee → automatic ADR / decision log for engineers | 3 | 3 | 3 | 4 | 4 | 3.35 |
| 11 | ~~Doorman~~ — natural-language Q&A over event history | 3 | 3 | 3 | 2 | 5 | **3.10** |
| 12 | Contractor arrival verification / timesheets | 3 | 3 | 3 | 2 | 4 | 2.95 |
| 13 | Package-theft detector | 3 | 3 | 3 | 1 | 4 | 2.75 |
| 14 | Gesture-passcode access control | 3 | 2 | 2 | 3 | 4 | 2.75 |

**Killed and why.** #11 "Doorman" (an earlier recommendation) is a chatbot wrapper over a REST endpoint —
it scores 2/5 on Quality of Idea because dozens of teams with Bedrock credits will submit the same thing;
its high feasibility masks a weak ceiling. #13 is the single most predictable Ring submission. #14 is
replay-attackable and judges will ask. #3 scores well but sits in a safety-critical domain where a
hackathon-grade false-negative rate is irresponsible to present as a product. #8 requires two device
ecosystems and fails the finishable-scope test.

The gap between #1 (4.85) and #2 (4.20) is ~13%, beyond the champion skill's 10% ambiguity threshold, so
the selection is decisive rather than a coin-flip.
