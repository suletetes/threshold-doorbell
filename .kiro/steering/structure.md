# Structure Steering — Threshold

## Repository layout

```
threshold-doorbell/
├── .kiro/
│   ├── specs/threshold-doorbell/     # requirements.md · design.md · tasks.md
│   └── steering/                     # product.md · tech.md · structure.md
├── app/                              # Flutter application (iOS + Android)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── ring/                     # RingClient, OAuth glue, WebRTC session
│   │   ├── captions/                 # CaptionEngine: Clarity (Transcribe) + Privacy (Whisper)
│   │   ├── reply/                    # ReplyAudioBridge (WebView pipeline) + TTS; audio_spike.dart
│   │   ├── alerts/                   # push handling, haptic vocabulary, strobe/torch
│   │   ├── ui/                       # screens: alert, conversation, reply bar, history, settings
│   │   └── a11y/                     # accessibility helpers (WCAG 2.2 AA)
│   ├── test/                         # unit + integration + a11y tests, fixtures
│   └── pubspec.yaml
├── backend/                          # Node 20 + Fastify (stateless)
│   ├── src/
│   │   ├── routes/                   # oauth, webhook, devices, events, signaling, asr, replies, transcripts
│   │   ├── services/                 # ring, transcribe, bedrock, store (+ fixtures)
│   │   ├── security/                 # hmac, session, secrets
│   │   └── observability/            # logging, metrics
│   └── package.json
├── packages/
│   └── flutter_ring_captions/        # extracted MIT package (Open Source mini-challenge)
├── docs/hackathon/                   # strategy, research, spec, improvements (context, not source of truth)
├── LICENSE                           # MIT
└── README.md
```

**Source of truth:** `.kiro/specs/threshold-doorbell/` and `.kiro/steering/`. The `docs/hackathon/` files are
strategy/research context; where they conflict with the spec, the spec wins.

## Architectural conventions

- **Ports & adapters.** Every external dependency (Ring, Transcribe, Bedrock, push, store) is an interface in
  `services/` with a real adapter and a fixture adapter. UI and domain logic depend on the interface, never
  the SDK directly. This is what makes offline tests and the demo build possible.
- **App layering (strict, one direction):** `ui/` → domain services → adapters. UI never calls an SDK or HTTP
  client directly; it goes through a Riverpod-provided service.
- **Backend layering:** `routes/` (schema-validated I/O) → `services/` (logic) → adapters. Routes hold no
  business logic; services hold no HTTP concerns.
- **State:** Riverpod providers only; no `BuildContext`-coupled singletons; no global mutable state.
- **The spike is quarantined.** `app/lib/reply/audio_spike.dart` is throwaway proof-of-capability. Once the
  approach is proven, promote the working pieces into `reply/` (bridge) and `ring/` (session) and delete the
  spike. Do not build UI on top of the spike file.

## UI copy rules (hard requirement)

- **Never use the em-dash character (`—`) in any user-facing UI string, label, notification, caption
  rendering, button, or on-screen text.** This is a firm product rule. It applies to every string the
  resident or visitor can see.
- Also avoid the en-dash (`–`) in UI copy. Use plain ASCII punctuation instead: a comma, a period, a colon,
  or a spaced hyphen ` - ` where a break is genuinely needed. Prefer two short sentences over a dash.
- This rule covers hardcoded strings AND any localized/generated copy, including Bedrock-suggested replies:
  the reply-rendering layer SHALL strip or replace em-dashes and en-dashes before display.
- A lint/CI check SHALL fail the build if an em-dash or en-dash appears in a UI string resource.
- Scope note: this rule is about UI text shown to users. Internal engineering docs and code comments are not
  UI and are not bound by it.

## Naming & style

- Dart: `lower_snake_case.dart` files; `UpperCamelCase` types; `lowerCamelCase` members. Lint: `flutter_lints`.
- Node: `kebab-case.ts`/`.js` files; `UpperCamelCase` types; ESLint + Prettier.
- Package name (pub): `flutter_ring_captions` (snake_case per Dart convention).
- One concern per file; keep files small and single-purpose.

## Data-flow contract (must hold)

```
Ring webhook ──► backend (verify HMAC, dedupe by requestId, 200 ≤5s) ──► push ──► app alert + haptic
Ring WebRTC ──► app (audio sendrecv / video recvonly) ──► inbound audio ──► CaptionEngine ──► captions
resident reply ──► TTS ──► ReplyAudioBridge (WebView) ──► outbound track ──► doorbell speaker
session end ──► text-only transcript persisted (never audio/video)
```

## Git & workflow conventions

- **All commits authored and committed by `suletetes <sulea841@gmail.com>`** — never the agent identity.
  Configure `user.name`/`user.email` accordingly for every commit.
- **Atomic commits:** one self-contained logical change per commit, conventional-commit message
  (`feat:`, `fix:`, `docs:`, `chore:`, `test:`). Split work into focused commits; no large bundles.
- Default branch: `main`. Never push CI config directly to `main` — always via PR. Never force-push `main`.
- Sign off commits (`git commit -s`) where the target repo requires DCO.

## Testing placement

- App unit/integration/a11y tests in `app/test/` mirroring `lib/` structure; fixtures alongside.
- Backend tests in `backend/test/` mirroring `src/`; contract tests validate every route against its schema.
- Every functional requirement (requirements.md §4) maps to ≥ 1 test; ≥ 80% line coverage on domain services.
