# Technology Steering — Threshold

## Stack (authoritative)

**Mobile app — Flutter / Dart** (Flutter ≥ 3.24, Dart ≥ 3.4). Targets iOS 14+ and Android 8.0 (API 26)+.

| Concern | Package / service | Pin (verify latest at build) |
|---|---|---|
| State management / DI | `flutter_riverpod` | ^2.6.0 |
| **Live session (video in, two-way audio)** | **`webview_flutter` + browser WebRTC + JS AudioContext pipeline** | ^4.7.0 |
| ~~Inbound WebRTC~~ (removed per ARCH-1) | ~~`flutter_webrtc`~~ | removed; see design.md |
| Text-to-speech | `flutter_tts` (uses `synthesizeToFile`) | ^4.2.0 |
| On-device ASR (Privacy Mode, stretch) | whisper.cpp via `whisper_ggml` / FFI | current |
| On-device vision | `google_mlkit_object_detection` | ^0.14.0 |
| Haptics | `vibration` | ^2.0.0 |
| Push | `firebase_messaging` (FCM; APNs via FCM) | ^15.x |

**Backend — Node 20 LTS + Fastify** (^4.28). Stateless, horizontally scalable.

| Concern | Service / lib |
|---|---|
| Cloud ASR (Clarity Mode, default) | Amazon Transcribe streaming (WebSocket, partial-results stabilization) |
| Smart replies | Amazon Bedrock (short text suggestions) |
| Secrets | AWS Secrets Manager (Ring client secret, HMAC key, AWS creds) |
| Store | DynamoDB (prod) / in-memory fixture (local, demo) |
| AWS SDK | `@aws-sdk/*` v3 |
| Logging | pino (structured, redacting) |

## Non-negotiable technical rules

1. **The mobile app never holds the Ring client secret or AWS credentials.** All privileged calls (OAuth
   exchange/refresh, Transcribe, Bedrock) go through the backend. Privacy-Mode ASR is the only on-device
   exception and touches no backend.
2. **Outbound audio uses the WebView pipeline, not raw flutter_webrtc track injection.** `flutter_webrtc`
   lists **Insertable Streams as unsupported on every platform** (verified on pub.dev and the repo). The
   browser inside a WebView supports `AudioContext → MediaStreamTrack`, which is the proven path. The only
   approved alternative is a native platform-channel PCM source. Do not attempt Insertable Streams.
3. **Prove the outbound-audio spike before building any UI.** It is the go/no-go for the architecture
   (tasks.md task 2, requirement FR-6, AT-5). Never mock this feature.
4. **Idempotent, fast webhooks.** Verify HMAC in constant time; dedupe by `requestId` via conditional put;
   return HTTP 200 within 5 s; offload push asynchronously.
5. **Respect Ring limits.** Never exceed 100 req/s; token-bucket throttle; exponential backoff with jitter
   on 429/5xx; refresh access token once on 401 and retry once.
6. **Never persist raw audio or video.** Only derived text. Privacy Mode has zero audio egress — enforced by
   a network-capture test.
7. **No PII, tokens, transcript text, or payload bodies in logs.** Redaction via a serializer allowlist.
8. **WebRTC session shape:** audio `sendrecv`, video `recvonly`; overlays kept out of the top corners to
   avoid the mandatory Ring watermark; keep the session alive for up to 5 minutes while backgrounded, then
   close the peer connection and release the session URL (FR-4.3a).
9. **Everything external is behind an interface with a fixture implementation** (Ring, Transcribe, Bedrock,
   push) so the app runs offline for tests and demo.

## Environments

- `local` — fixtures only, no AWS, no real Ring.
- `staging` — real AWS, Ring staging users (≤ 10), Playground/OAuth tokens.
- `demo` — deterministic fixtures + cached golden ASR/Bedrock responses so a network or rate-limit hiccup
  never breaks the live demo. The outbound-audio path stays real.

## Commands (baseline)

```bash
# App
cd app && flutter pub get && flutter run
flutter test

# Backend
cd backend && npm ci && npm run dev
npm test
```

## CI/CD rules

- PR gates: lint + unit + contract + accessibility scan. A build with any WCAG 2.2 AA violation does not merge.
- Never push CI config directly to `main` — always via PR.
- Deploy on merge to `main` after gates pass. Backend runs ≥ 2 stateless instances with least-privilege IAM
  per AWS service.

## Performance budgets (enforce in tests)

- Doorbell event → first caption ≤ 3.0 s (Clarity, good network).
- Caption partial latency ≤ 1.0 s after speech onset.
- Reply tap → audio audible at door ≤ 2.0 s.
