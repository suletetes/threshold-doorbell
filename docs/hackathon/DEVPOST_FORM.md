# Devpost Submission Form: Threshold

Copy-paste answers for every field on the Devpost form. Character limits from the
form are noted. No em-dash or en-dash anywhere (screen-reader consistency, our
product rule). Architecture diagrams to attach are in `docs/hackathon/diagrams/`.

---

## General info

### Project name (max 60 characters)

```
Threshold
```

Alternate if you want the descriptor inline (57 chars):
```
Threshold: the doorbell that speaks your language
```

### Elevator pitch (max 200 characters)

```
A video doorbell for people who cannot hear it. Live captions of what your visitor says, and a tap-to-speak reply spoken back out the door. A full two-way conversation, no hearing required.
```
(198 characters.)

---

## Project Story

### About the project

> Inspiration, what it does, how we built it, what we learned, and the
> challenges. Markdown is supported.

#### Inspiration

Priya is 34, profoundly deaf, and lives alone. She owns a Ring doorbell and it
works exactly as designed: she gets a phone alert and sees a man at her door.
Then the interaction dies. He is saying something, maybe which flat he wants, or
whether to leave the parcel next door, and she has no access to any of it. Her
only options are to ignore the door or open it to a stranger and mime. Her
doorbell tells her someone is there. It has never once told her what they want.

We looked at the whole market for deaf and hard-of-hearing doorbells. Every
product solves the same half of the problem: alerting. Strobe lights, flashing
chimes, extra-loud chimes, vibrating pagers. Not one solves the conversation.
The real incumbent is ambient captioning like Google Live Transcribe, but that
captions the room you are standing in; it cannot tap the doorbell stream, and it
is one-way, so it can never reply through the door. That gap is the whole idea.

#### What it does

Threshold turns a Ring doorbell into a two-way, text-first conversation device.

1. A person-detected webhook fires. The phone plays a distinct haptic pattern
   (a deaf user cannot rely on a chime) and shows the visitor thumbnail.
2. The resident taps Open. A Ring WebRTC session starts: audio both ways, video
   inbound.
3. The visitor speaks. Captions stream in, large and high-contrast, styled by
   confidence so uncertain words look uncertain rather than being presented as
   fact.
4. Three contextual smart replies appear next to a free-text field.
5. The resident taps a reply. On-device text-to-speech turns it into audio, that
   audio is injected into the outbound track, and the visitor hears it spoken
   from the doorbell. The visitor answers, and captions continue.
6. The whole exchange is saved as a searchable transcript of what was said at
   the door.

Two capture modes: Clarity Mode (Amazon Transcribe streaming, the default) and
Privacy Mode (on-device Whisper, so doorstep audio never leaves the handset).

#### Architecture

![System overview](diagrams/01-system-overview.svg)

![Inbound caption flow](diagrams/02-inbound-caption-flow.svg)

![Outbound reply flow, ARCH-1](diagrams/03-outbound-reply-flow.svg)

![Event and alert flow](diagrams/04-alert-event-flow.svg)

#### How we built it

- Flutter app (iOS and Android), Riverpod state, built to a real design system
  (tokens, themed components, light and dark) rather than one-off screens.
- Node and Fastify backend: Ring OAuth exchange and refresh, an idempotent
  webhook receiver (HTTP 200 within the required 5 seconds), an Amazon Transcribe
  streaming relay, an Amazon Bedrock smart-reply call, and conversation storage.
  The logger enforces a redaction allowlist so tokens, PII, and transcript text
  never reach the logs.
- Ring Partner API over WebRTC and WHEP. The session negotiates audio as
  sendrecv, the bidirectional channel Amazon's own sample renders but never sends
  into. Reply audio is injected through an in-app WebView audio pipeline (ARCH-1).
- Amazon Transcribe streaming (Clarity captions) with partial-results
  stabilization; Amazon Bedrock for bounded three-option smart replies; on-device
  Whisper for Privacy Mode.
- Accessibility throughout: WCAG 2.2 AA, a 4.5:1 caption contrast floor, 200%
  text scaling, a haptic vocabulary, screen-reader support, reduced-motion.

#### What we learned

- Position on two-way, never on captions. If the demo could be replaced by
  pointing Live Transcribe at the door, the pitch is wrong.
- De-risk the one thing that can kill the project first. We spiked outbound audio
  before building any UI, and that ordering shaped the whole build.
- A streaming relay must treat "audio before the upstream is ready" as normal,
  not an error.
- Prove redaction by asserting on serialized log output, not by trusting config.
- On Flutter, ship the cloud caption path (Transcribe) as the default and treat
  on-device Whisper as a bonus. Reliability wins demos.

#### Challenges we ran into

- Getting audio out of the doorbell at all was the single hardest unknown. Ring's
  audio is sendrecv, but the canonical sample only renders the inbound half.
- flutter_webrtc does not expose Insertable Streams, the clean way to inject a
  synthesised frame into an outbound track. So we moved the audio pipeline into a
  WebView, where the AudioContext to MediaStreamTrack path is well-trodden, and
  drove the outbound track from there. That decision (ARCH-1) was made early and
  deliberately, not patched in at the end.
- WebSocket close-code propagation over the in-process test transport did not
  surface reliably within a tick, so we assert the server-initiated close path
  directly and poll a fixture for the disconnect path.

### Built with (up to 25 tags)

```
flutter, dart, riverpod, webrtc, webview, node.js, fastify, typescript,
amazon-transcribe, amazon-bedrock, aws, ring, ring-partner-api, whisper,
whisper.cpp, on-device-ai, dynamodb, aws-kms, fcm, accessibility, wcag,
flutter-tts, google-ml-kit, material-design
```
(24 tags.)

### Try it out links

```
Code repository: https://github.com/suletetes/threshold-doorbell
Demo video: <paste your YouTube or Vimeo link, public, under 3 minutes>
Open-source package: https://github.com/suletetes/threshold-doorbell/tree/main/packages/flutter_ring_captions
```

---

## Judging fields

### GitHub repository URL

```
https://github.com/suletetes/threshold-doorbell
```
The repository is public and MIT-licensed, with the license visible in the About
section. It contains all source code, assets, and run instructions (app, backend,
package, specs, and diagrams).

### If submitting an existing project, what did you update during the window?

This project was built entirely within the hackathon window; it is not a
rebrand of a pre-existing product. Everything created during the window: the
outbound-audio spike and the resulting ARCH-1 WebView audio-injection decision;
the Flutter app and its elevation to a design-system-driven UI; the Node and
Fastify backend (Ring OAuth and refresh, the idempotent webhook receiver, the
Amazon Transcribe streaming relay, the Amazon Bedrock smart-reply call,
conversation storage, and a redaction-tested logger); Clarity Mode and Privacy
Mode; the haptic vocabulary and the WCAG 2.2 AA accessibility pass; the
flutter_ring_captions open-source package; the full automated test suite; and the
release-size work (ABI split, R8 and resource shrinking, obfuscated app bundle)
that cut the per-device arm64 download from about 113 MB to about 44 MB.

### AWS Builder Mini Challenge: which AWS services did you incorporate and how?

Yes, we are submitting for the AWS Builder Mini Challenge. Threshold uses two AWS
services as load-bearing parts of the pipeline, not as decoration:

- Amazon Transcribe (streaming) is the default caption engine (Clarity Mode).
  Visitor audio from the Ring WebRTC session is relayed through the backend to
  Amazon Transcribe streaming over a WebSocket, using partial-results
  stabilization so live partial captions do not thrash as they finalize.
  Integration lives in the backend ASR relay (`/asr/stream`) and its Transcribe
  service adapter. This is what lets a deaf resident read what the visitor is
  saying in close to real time.
- Amazon Bedrock generates the three contextual smart replies from the running
  transcript. It is scoped tightly to short, bounded suggestions (never
  open-ended chat), which keeps it off the latency-critical path and keeps the
  product an assistive bridge rather than a chatbot. Integration lives in the
  backend `/replies` route and its Bedrock service adapter, and it is called only
  in Clarity Mode (Privacy Mode never sends transcript text off the device).

Supporting AWS services in the design: Amazon DynamoDB with AWS KMS for
KMS-encrypted token storage and text-only transcript persistence with a 90-day
TTL. Together, Transcribe (perception) and Bedrock (bounded synthesis) are the
AWS half of the pipeline that turns doorbell audio into an accessible
conversation.

### Are you submitting for the Open Source Mini Challenge? (yes / no)

```
Yes
```

- Contribution URL: `<paste your PR URL to AmazonAppDev/ring-api-helloworld once opened; see OSS_PR_GUIDE.md>`
- Project repository URL: `https://github.com/suletetes/threshold-doorbell`
- GitHub username: `suletetes`
- What we did, how it works, why it matters: We published the caption-and-reply
  bridge as a standalone MIT-licensed Dart package, `flutter_ring_captions`, so
  any Flutter developer building on the Ring Partner API can reuse the two-way
  captioning core without adopting the whole Threshold app. The main repository
  is MIT-licensed with the license visible. We also open a focused,
  accessibility-oriented pull request to Amazon's `AmazonAppDev/ring-api-helloworld`
  sample (a `VideoProcessor` that demonstrates a caption or high-contrast overlay
  for deaf and hard-of-hearing users), whose CONTRIBUTING.md welcomes focused PRs.
  It matters because it turns a one-off hackathon feature into reusable
  infrastructure for accessible Ring integrations.

---

## Feedback questions

### 1. Which developer tools, APIs, and SDKs did you use and for what?

- Ring Partner API (WebRTC / WHEP): the live doorbell session, device discovery,
  motion and person events, and the sendrecv audio channel that carries both the
  visitor's speech and our spoken reply.
- Amazon Transcribe (streaming): real-time visitor captions in Clarity Mode.
- Amazon Bedrock: bounded, three-option contextual smart replies.
- Amazon DynamoDB and AWS KMS: KMS-encrypted token storage and text-only
  transcript persistence with a TTL.
- Flutter and Dart: the cross-platform app. flutter_webrtc, webview_flutter, and
  flutter_tts for the media and reply path; flutter_local_notifications for
  alerts; google_mlkit_object_detection for on-device visual context; vibration
  for the haptic vocabulary; flutter_riverpod for state.
- whisper.cpp (on-device): Privacy Mode transcription with no audio egress.
- Node and Fastify: the backend (OAuth, webhook, signaling, ASR relay, replies,
  persistence). Vitest for backend tests; flutter_test for the app.

### 2. For each tool, what worked well?

- Ring Partner API: the WHEP live-view flow is clean, and events carry a
  thumbnail and confidence out of the box, which made the alert screen simple.
- Amazon Transcribe: partial-results stabilization is purpose-built for live
  captioning and behaved exactly as documented; streaming setup was
  straightforward.
- Amazon Bedrock: fast to call for short bounded generations; reliable for the
  three-suggestion use case and easy to keep off the latency-critical path.
- Flutter: flutter_test compiles all Dart and runs the full unit and widget
  suite quickly, which made it our primary and most reliable gate. The Material 3
  theming system let us build a real design system.
- DynamoDB and KMS: envelope encryption of tokens and a TTL for transcript
  retention mapped cleanly onto the data model.

### 3. For each tool, what needs work?

- flutter_webrtc: no Insertable Streams or custom-audio-source API, so injecting
  a synthesised frame into an outbound track is not possible directly. This is
  the single biggest gap we hit and it forced the WebView audio approach. Exposing
  Insertable Streams would remove that shim entirely.
- Ring Partner API: the canonical sample renders only the inbound half of the
  sendrecv channel, so it is not obvious that you can send audio back. A short
  official note on how to drive the outbound track would help every team wanting
  two-way talk. The Playground token also expires in roughly 30 minutes, which
  causes repeated re-authentication during a build sprint.
- flutter_local_notifications: requires core library desugaring for java.time on
  older API levels, but the build error does not name desugaring as the cause;
  the exact snippet belongs near the top of the Android setup docs.
- Flutter tooling: `flutter analyze` crashed in our constrained build environment
  with a file-descriptor limit ("Too many open files") rather than degrading
  gracefully; we used `dart analyze` with a raised ulimit instead.
- Android and Gradle: Java 25 broke the Gradle build with an opaque error; the
  supported JDK range (17 or 21) should fail fast and be documented prominently.

### 4. For each tool, how was your onboarding experience (zero to hello world)?

- Ring Partner API: fast to a first live view thanks to the Playground token (no
  full OAuth app needed to start), though the short token lifetime meant the
  "hello world" kept expiring during longer sessions.
- Amazon Transcribe and Bedrock: smooth from zero to a working call; the
  streaming and text-generation quickstarts matched reality.
- Flutter: quick to a running app, but the missing android/ directory case (a
  lib-only project cannot build an APK) produced a generic Gradle error rather
  than a clear "run flutter create --platforms=android" hint, which slowed the
  first real build.
- Backend (Fastify, AWS SDK v3): fast; the SDK v3 modular clients for Transcribe
  and Bedrock were easy to wire behind interfaces with fixtures for testing.

### 5. Would you build with these devices and services again? (yes / no and why)

Yes. The Ring Partner API plus Amazon Transcribe and Bedrock is a genuinely
strong stack for an accessibility product: Ring reaches the door, Transcribe
turns speech into readable text in real time, and Bedrock adds bounded, useful
reply suggestions without becoming a chatbot. The friction we hit was mostly at
the edges (a WebRTC plugin gap, token lifetime, a few opaque build errors) and
every one had a clean workaround. The core capability, a two-way conversation at
the door for people who cannot hear it, is only possible because these services
compose well, so we would absolutely build on them again.
