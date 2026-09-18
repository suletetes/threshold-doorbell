# Threshold

**The first video doorbell experience built for the people who can't hear it.**

Live captions of what your visitor is saying, and a tap-to-speak reply spoken aloud out of the
doorbell — a complete two-way conversation, no hearing required.

Built for the **Amazon Developer Hackathon 2026** · **Ring** track · **Flutter** (iOS + Android)
Mini-challenges: **AWS Builder** (Amazon Transcribe + Bedrock) · **Open Source** (`flutter_ring_captions`)

> *threshold* — the audiology term for the quietest sound a person can detect, and the place where a
> visitor stands. Both meanings are the product.

---

## The problem

A deaf person's Ring doorbell tells them *someone* is at the door. It never tells them *what that person
is saying*. Every existing "deaf doorbell" product only solves the alert — brighter lights, louder chimes,
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
| Live video + two-way audio | `flutter_webrtc` |
| Captions — default (accuracy) | Amazon Transcribe streaming |
| Captions — Privacy Mode (stretch) | on-device Whisper (`whisper_ggml` / FFI to whisper.cpp) |
| Smart replies | Amazon Bedrock |
| Reply spoken at the door | `flutter_tts` |
| Distinct alert patterns | `vibration` (haptic vocabulary) |
| Visual context | `google_mlkit_object_detection` / `tflite_flutter` |
| Ring integration | Ring Partner API (OAuth 2.0 + webhooks), backend |

## Repository layout

```
.
├── app/                    # Flutter application (see app/README.md)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── ring/           # Ring API client, WebRTC session, OAuth
│   │   ├── captions/       # ASR (Transcribe + on-device), caption stream
│   │   ├── reply/          # TTS + reply injection into outbound audio
│   │   ├── alerts/         # haptic vocabulary, notifications
│   │   ├── ui/             # screens: alert, conversation, reply bar, history
│   │   └── a11y/           # accessibility helpers (WCAG 2.2 AA)
│   └── pubspec.yaml
├── docs/hackathon/         # strategy, spec, plain-English explainer
│   ├── threshold-explained.md
│   ├── threshold-spec.md
│   └── research-and-scoring.md
└── LICENSE                 # MIT
```

## Status

Pre-implementation. **Job #1 is the audio spike** (see `docs/hackathon/threshold-spec.md` §9 R1): prove a
synthesised voice can be injected into the outbound WebRTC track and heard at the door, before building any
UI. This is the go/no-go for the whole architecture.

## Getting started

```bash
cd app
flutter pub get
flutter run
```

You will need a Ring developer account, an OAuth app, and a Ring Protection plan for full device testing —
see `docs/hackathon/threshold-spec.md` §11 for the day-by-day plan.

## License

[MIT](./LICENSE)
