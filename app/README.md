# Threshold — Flutter app

The mobile client (iOS + Android). See the repo root `README.md` for the product overview and
`../docs/hackathon/threshold-spec.md` for the full engineering spec.

## Structure

```
lib/
├── main.dart          # entry point (placeholder home until UI is built)
├── ring/              # Ring API client, OAuth, WebRTC session (audio sendrecv / video recvonly)
├── captions/          # ASR: Amazon Transcribe (default) + on-device Whisper (Privacy Mode, stretch)
├── reply/             # TTS + injecting the reply into the outbound audio track
│   └── audio_spike.dart   # ⚠️ START HERE — the R1 go/no-go spike
├── alerts/            # haptic vocabulary, local notifications
├── ui/                # screens: alert, conversation, reply bar, transcript history, settings
└── a11y/              # accessibility helpers (WCAG 2.2 AA, large text, contrast, screen reader)
```

## First run

```bash
flutter pub get
flutter run
```

## Build order (from the spec)

1. **Audio spike** (`lib/reply/audio_spike.dart`) — prove the doorbell can speak. Go/no-go.
2. Ring WebRTC session + inbound video/audio (`lib/ring/`).
3. Webhook-driven alert + haptic vocabulary (`lib/alerts/`).
4. Streaming captions via Amazon Transcribe (`lib/captions/`).
5. Reply bar + TTS out the door (`lib/reply/`).
6. Bedrock smart replies, transcript history, accessibility pass.

On-device Whisper (Privacy Mode) is a stretch goal added after Clarity Mode works — see the commented
dependency in `pubspec.yaml`.
