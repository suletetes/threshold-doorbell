# Threshold - Devpost submission

> The first video doorbell experience built for the people who cannot hear it.
> Live captions of what your visitor is actually saying, and a tap-to-speak
> reply sent back out through the doorbell. A complete two-way conversation, no
> hearing required.

Track: Ring. Mini-challenges entered: AWS Builder and Open Source.
Platform: Flutter (iOS and Android).

## Inspiration

Priya is 34, profoundly deaf, and lives alone. She already owns a Ring
doorbell, and it works exactly as designed: she gets a phone alert and sees a
man standing at her door. Then the interaction dies. He is saying something,
maybe which flat he wants, whether to leave the parcel next door, whether he
needs a signature, and she has no access to any of it. Her only options are to
ignore the door or open it to a stranger and mime.

Her doorbell tells her that someone is there. It has never once told her what
they want.

We looked at the whole market for deaf and hard-of-hearing doorbells, and every
product solves the same half of the problem: alerting. Strobe lights, flashing
chimes, extra-loud chimes, vibrating pagers. Not one solves the conversation.
The real incumbent is ambient captioning like Google Live Transcribe, but that
captions the room you are standing in; it cannot tap the doorbell stream, and it
is one-way, so it can never reply through the door. That gap is the whole idea.

## What it does

Threshold turns a Ring doorbell into a two-way, text-first conversation device.

1. A `person_detected` webhook fires. The phone plays a distinct haptic pattern
   (deaf users cannot rely on a chime) and shows the visitor thumbnail
   full-bleed.
2. The resident taps Open. A Ring WebRTC session starts: audio both ways, video
   inbound.
3. The visitor speaks. Captions stream in, large and high-contrast, styled by
   confidence so uncertain words look uncertain instead of being presented as
   fact.
4. Three contextual smart replies appear next to a free-text field.
5. The resident taps a reply. On-device text-to-speech turns it into audio, that
   audio is sent up the outbound track, and the visitor hears it spoken from the
   doorbell. The visitor answers, and captions continue.
6. The whole exchange is saved as a searchable transcript of what was said at
   the door, an artifact nothing else on the market produces.

Two capture modes: Clarity Mode (Amazon Transcribe streaming, the default) and
Privacy Mode (on-device Whisper, so doorstep audio never leaves the handset).

## How we built it

- **Flutter app (iOS and Android).** Mobile is intrinsic, not decorative: the
  alert has to be haptic and on the body, captions have to be readable where the
  user actually is, and the reply has to be one thumb fast while a stranger
  waits. A desktop dashboard cannot buzz in a pocket. State is managed with
  Riverpod; the whole app is built to a design system rather than one-off
  screens.
- **Node/Fastify backend.** Everything below the app is plain HTTP and
  WebSocket: Ring OAuth token exchange and refresh, the webhook receiver
  (returns HTTP 200 within the required five seconds, idempotent on
  `request_id`), an Amazon Transcribe streaming relay, an Amazon Bedrock call for
  smart replies, and conversation persistence. The logger runs a strict
  allowlist so tokens, PII, and transcript text never reach the logs.
- **Amazon Transcribe streaming** powers Clarity Mode captions. We use partial
  results stabilization, which is purpose-built for live captioning, and buffer
  early audio so frames that arrive before the upstream stream is ready are
  treated as normal rather than as an error.
- **Amazon Bedrock** generates the three contextual smart replies from the
  running transcript. It is deliberately not a chatbot: perception
  (speech to text), synthesis (text to speech), and at most a three-option reply.
- **On-device Whisper** (whisper.cpp via FFI) backs Privacy Mode, gated by
  Silero-style voice activity detection so noise does not drive inference. This
  is the privacy stretch goal; Clarity Mode carries the demo either way.
- **Ring Partner API over WebRTC/WHEP.** The session negotiates audio as
  `sendrecv`, the bidirectional channel that Amazon's own sample renders but
  never sends into. The outbound reply audio is injected through an in-app
  WebView audio pipeline (the ARCH-1 approach, described under Challenges below).
- **Design system and accessibility work** run through the whole app: a shared
  token set, themed components, a UI-copy lint that blocks forbidden dashes in
  every user-facing string, and a haptic vocabulary.

## Accessibility

Accessibility is the product, not a feature bolted onto it.

- Built to **WCAG 2.2 AA**, which Ring's own partner UX guide mandates.
- Captions honor a **4.5:1 minimum contrast floor** and stay legible at large
  sizes.
- Full support for **200% text scaling** without clipping or overlap.
- A **haptic vocabulary**: distinguishable vibration patterns for
  person-at-door, motion, and conversation-started, so the phone becomes the
  doorbell.
- Complete **screen-reader support** (TalkBack and VoiceOver): the app is fully
  usable with the screen off.
- **Reduced-motion** support: every animation respects the platform
  reduce-motion setting.
- Confidence styling on captions so a low-confidence guess is never presented as
  certain, which matters when a stranger is at the door.

## Challenges we ran into

- **The R1 outbound-audio spike.** The single hardest unknown was whether we
  could get synthesised audio out of the doorbell at all. Ring's WebRTC audio is
  `sendrecv`, but Amazon's canonical sample only ever renders the inbound half.
  We treated this as a go/no-go and spiked it before building any UI, because
  the entire product depends on the doorbell being able to speak.
- **flutter_webrtc has no Insertable Streams.** The clean way to inject a
  synthesised audio frame into an outbound WebRTC track is the Insertable
  Streams API, and the Flutter WebRTC plugin does not expose it. Feeding
  generated PCM directly into a native audio track was not a reliable path.
- **The WebView pipeline decision (ARCH-1).** Rather than mock the feature the
  judges came to see, we moved the audio pipeline into an in-app WebView, where
  the browser `AudioContext` to `MediaStreamTrack` injection path is
  well-trodden, and drove the outbound track from there. That decision was made
  early and deliberately, not patched in at the end.
- **WebSocket lifecycle under test.** Close-code propagation over the in-process
  test transport did not reliably surface within a single tick, so we assert the
  server-initiated close path directly and poll a fixture for the disconnect
  path instead of racing an event.

## Accomplishments that we are proud of

- **A complete two-way conversation at the door**, using the channel the rest of
  the ecosystem leaves idle.
- **Over 500 automated tests** in the app suite (567 passing), plus a dedicated
  package test suite, covering captions, replies, haptics, accessibility, and
  the design system.
- **A full design system**, not a pile of screens: shared tokens, themed
  components, and a copy lint wired into CI.
- **An ABI-split, obfuscated release build** that cuts the real per-device
  download from about 113 MB to about 44 MB on a modern phone, documented and
  reproducible.
- **Privacy that is architectural, not marketing:** Privacy Mode runs the whole
  speech pipeline on the handset, a claim anyone can check.

## What we learned

- Position on two-way, never on captions. If the demo could be replaced by
  pointing Live Transcribe at the door, the pitch is wrong. Lead with the
  resident replying and the doorbell speaking.
- De-risk the one thing that can kill the project first. The audio spike came
  before any UI, and that ordering shaped the whole build.
- A streaming relay must treat "audio before the upstream is ready" as a normal
  case, not an error, or reconnect-with-replay will flake.
- Prove redaction by asserting on serialized log output, not by trusting the
  config.
- On Flutter, ship the cloud caption path (Transcribe) as the default and treat
  on-device Whisper as a bonus. Reliability wins demos.

## What's next

- Land the on-device Whisper Privacy Mode fully on mid-range Android.
- Live translation for non-English visitors (explicitly a nice-to-have, kept out
  of the core so it cannot destabilise the demo).
- A wearable relay for wrist haptics, and screen-strobe plus torch as a free
  software replacement for the flashing-light hardware this market sells.
- The Ring App Store certification path. We are honest that a shipping product
  needs an active Ring Protection subscription and certification; the hackathon
  demo runs on a Playground token and staging users, which is ungated.
- Making ML Kit object detection an optional or deferred module for
  size-critical, low-connectivity markets (see `APK_SIZE.md`).

## Mini-challenge: AWS Builder

Threshold uses two AWS services as load-bearing parts of the product, not as
decoration:

- **Amazon Transcribe (streaming).** This is the default caption engine (Clarity
  Mode). Visitor audio from the Ring WebRTC session is relayed through the
  backend to Amazon Transcribe streaming over a WebSocket, and we use partial
  results stabilization so live partial captions do not thrash as they finalize.
  Transcribe is what lets a deaf resident read what the visitor is saying in
  close to real time.
- **Amazon Bedrock.** The three contextual smart replies are generated by
  Bedrock from the running transcript. It is scoped tightly to short, bounded
  reply suggestions (never open-ended chat), which keeps it off the latency
  critical path and keeps the product an assistive bridge rather than a chatbot.

Together, Transcribe (perception) and Bedrock (bounded synthesis) are the AWS
half of the pipeline that turns doorbell audio into an accessible conversation.

## Mini-challenge: Open Source

We published the caption-and-reply bridge as a standalone MIT-licensed Dart
package, **`flutter_ring_captions`**, so any Flutter developer building on the
Ring Partner API can reuse the two-way captioning core without adopting the
whole Threshold app. The main repository is MIT-licensed with the license
visible in the repository, and the accessibility-oriented video-processor work
is written against Ring's own `VideoProcessor` plugin contract so it reads as
native to their ecosystem. Our intended open-source contribution back to the
community also includes a focused, accessibility-oriented pull request to
Amazon's `AmazonAppDev/ring-api-helloworld` sample, whose `CONTRIBUTING.md`
explicitly welcomes focused PRs.

## What changed during the hackathon window

This project was built inside the hackathon window. Work completed during the
window includes: the R1 outbound-audio spike and the resulting ARCH-1 WebView
audio-injection decision; the Flutter app skeleton and its full elevation to a
design-system-driven UI; the Node/Fastify backend (Ring OAuth and refresh,
idempotent webhook receiver, the Amazon Transcribe streaming relay, the Amazon
Bedrock smart-reply call, conversation persistence, and a redaction-tested
logger); Clarity Mode and Privacy Mode capture paths; the haptic vocabulary and
the WCAG 2.2 AA accessibility pass; the `flutter_ring_captions` open-source
package; the full automated test suite (567 app tests passing); and the release
size work (ABI split, R8 and resource shrinking, obfuscated app bundle) that
brought the per-device arm64 download from about 113 MB down to about 44 MB. No
pre-existing product was rebranded for this submission; the doorbell, captions,
reply path, and accessibility work were all created for this hackathon.
