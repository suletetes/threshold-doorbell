# Threshold full-implementation audit (branch `feat/device-tier-ui-and-a11y`)

This is a behavioral audit of the entire stacked Threshold codebase: a Node 20 + Fastify + TypeScript
backend (45 files), a Flutter/Dart app (43 files), and the extracted `flutter_ring_captions` package (5
files), checked against `.kiro/specs/threshold-doorbell` and `.kiro/steering`. All 186 backend vitest and
265 flutter tests pass; this review is about what those tests do not catch. The backend is genuinely solid
on the security primitives it exercises (PKCE, signed CSRF state, constant-time HMAC, KMS-shaped envelope
crypto, log redaction, refresh-once-on-401, webhook idempotency, sticky-mode logic). The gaps are almost all
of one kind: **decision logic is written and unit-tested, but nothing in production actually calls it**, plus
one concrete cross-resident data leak on the event feed.

Watch for: the `/events` feed returns every resident's door events to any authenticated caller because the
event store has no `residentSub` dimension at all (confirmed) - the transcript feed is scoped but the event
feed is not, and AT-19 names both. The live caption surface renders a hardcoded placeholder string; the
confidence-styling, turn-segmentation, on-device-suggestion, echo-gap-marking, and model-provisioning modules
are unit-tested pure logic with no widget or controller consuming them (confirmed), so several acceptance
behaviors (AT-4 rendering half, AT-18 gap marking, FR-7.1a on-device suggestions) have no production path.
The 200% textScaler clamp and the caption contrast floor are enforced only on the Settings screen, not on the
screens that show captions (confirmed).

**Verdict**: NEEDS_CHANGES

## High-level view

The backend authorization model is correct for transcripts and wrong for events. Every transcript route
derives `residentSub` from the verified session and rejects a foreign one with 403, and the store is keyed by
resident. The event path never got the same treatment: `EventStorePort.listOrdered(since)` takes no resident
argument, `MemoryEventStore` returns all rows, and `design.md` §3 defines the `events` table with PK
`requestId` and no resident dimension, so `/events` structurally cannot scope per resident. In the fixture
every event happens to map to one demo resident, which is why the tests stay green, but in any multi-resident
deployment this is a cross-resident read of event type, timestamp, deviceId, and thumbnailUrl.

The rest of the backend holds up under reading (PKCE-verifier-in-signed-state, refresh-once-on-401,
100 rps hard cap, ack-before-push). The one backend correctness nit is the ASR replay buffer is never
cleared after a reconnect replay, harmless only because `MAX_RECONNECTS` is 1.

The app is a large set of well-factored, well-tested pure modules that have not been composed into a running
product. `main.dart` is still the skeleton that points at the audio spike; there is no `ProviderScope`, no
composition root, and the spike file the steering says to delete after promotion is still present. The caption
screens draw a static "Captions appear here" string rather than rendering `CaptionTurn`s, so the confidence
emphasis logic (partial provisional, final below 0.6 de-emphasized, 0.6 inclusive normal) is exercised only in
unit tests. On-device Privacy-Mode suggestions, the echo-gate transcript-gap marking, and the model-download
gate are all implemented and tested but nothing calls them.

Accessibility is strong in the widgets that exist (Semantics labels, live regions, header roles, non-alarming
Captions-Only banner, exact required banner strings, dash-free copy throughout), but two enforced invariants
leak: the OS text-scaling clamp to 200% and the 4.5:1 caption contrast floor are applied on the Settings
screen only, not on the conversation or Captions-Only screens where captions actually render.

The API surface adds no new user-facing dashes anywhere (verified by scan across backend, app, and package),
and the dash-stripping is duplicated correctly in three places (`ui-copy.ts`, `reply_bridge.dart`,
`ondevice_suggestions.dart`/`reply_suggestions.dart`).

<details>
<summary>Issues (11)</summary>

1. **Cross-resident event leak** (confirmed, P1) - `/events` returns all residents' events because
   `EventStorePort`/`MemoryEventStore` and the `events` table schema have no `residentSub` dimension. Add
   resident scoping to the event store key, the port signature, and the route, and add an AT-19 test that
   seeds two residents and asserts isolation.
2. **Caption rendering has no production widget** (confirmed, P1) - `CaptionTurn`, `CaptionEmphasis`, and
   `TurnAccumulator` are never consumed; the conversation and Captions-Only screens show a hardcoded string.
   AT-4's rendering half and FR-5.3/5.3a have no real UI. Build a caption widget that renders turns with the
   emphasis styling.
3. **textScaler clamp and contrast floor not applied to captions** (confirmed, P1) - the 200% clamp and the
   4.5:1 floor are enforced only in `SettingsScreen`; the caption screens use hardcoded `fontSize: 22` and do
   not consume `captionScale` or `captionForeground`. Wire the settings into the caption surface (NFR-2,
   FR-10.2, AT-9).
4. **On-device Privacy-Mode suggestions never wired** (confirmed, P2) - `onDeviceSuggestions` (FR-7.1a) is
   tested but nothing computes `contextualSuggestions` for the reply bar in either mode. Wire Clarity to
   `/replies` and Privacy to `onDeviceSuggestions`.
5. **Echo-gate transcript-gap marking never invoked** (confirmed, P2) - `EchoGate.settle()`/`gaps`
   (FR-5.6 gap marking, AT-18) are never called in production; `ReplyController` opens and closes the gate in
   the same synchronous tick and never records the gap into a transcript. Drive `settle()` on a timer and
   persist the gap.
6. **Model-download gate and recording-notice fallback not wired to sessions** (confirmed, P2) -
   `ModelProvisioningMachine` (FR-5.2a) and `RecordingNoticeController.resolveSessionStart` (FR-14.3a) are
   tested but no session flow consults them before starting Privacy Mode or transcription.
7. **No composition root** (confirmed, P2) - `main.dart` is a placeholder pointing at the spike; there is no
   `ProviderScope` assembling the controllers, so no end-to-end path exists behind AT-1..AT-25 beyond unit
   fixtures. Add the composition root and integration wiring.
8. **Quarantined spike still present** (confirmed, P2) - `app/lib/reply/audio_spike.dart` is still in the tree
   though `reply/` now holds the promoted port and controller; steering says delete it after promotion.
9. **ASR replay buffer not cleared after replay** (confirmed, P2) - `AsrRelay.reconnect` replays the buffer
   but never calls `buffer.clear()`, so a second reconnect would replay stale audio; masked only because
   `MAX_RECONNECTS` is 1. Clear after a successful replay.
10. **`deriveResidentSub` can collide across accounts** (confirmed, P2) - stripping the `access-`/`refresh-`
    prefixes means code `account-42` and code `refresh-account-42` map to the same sub. Fixture-only today
    (the real adapter is meant to call Ring identity), but the token-derived-identity pattern is
    security-sensitive; derive the sub from an opaque identity response, not the token string.
11. **UI-copy dash lint misses triple-quoted and raw strings** (confirmed, P2) - `scanSource` toggles on
    single/double quotes only; Dart `'''`/`"""` and `r'...'` strings are not modeled, so a dash inside them
    could pass CI (AT-24 fidelity). Extend the scanner or lint the rendered strings.

</details>

<details>
<summary>Details</summary>

### Event feed is not resident-scoped while the transcript feed is

The transcript path is a good model of the authorization rule: `registerTranscriptRoutes` pulls
`request.session!.sub`, `TranscriptService.buildConversation` rejects a conflicting client `residentSub` with
403, `MemoryConversationStore` is keyed `Map<residentSub, Map<conversationId, Conversation>>`, and the
authorization suite proves resident-a cannot read or delete resident-b's transcript. The event path never got
this. `EventStorePort` declares `listOrdered(since?: string)` with no resident argument; `MemoryEventStore`
holds a single `Map<requestId, DoorEvent>` and returns all of it; and `design.md` §3 defines
`events: PK requestId, TTL 7 days` with no resident attribute, so the leak is baked into the schema, not just
the fixture.

```
GET /transcripts  ->  service.list(residentSub, ...)  ->  store scoped by residentSub   (isolated)
GET /events       ->  eventStore.listOrdered(since)   ->  every resident's events        (leak)
```

`events.ts` even comments the gap out loud: "residentSub scoping happens at the store level in the real
deployment. In the fixture the event store is the resident's event feed." That is not true once more than one
resident exists, and AT-19 explicitly requires that "the transcript **and event** lists paginate with a
stable cursor; a request supplying a foreign residentSub is rejected and returns only session-scoped data."
The `devices-events.test.ts` AT-19 case for events asserts only pagination and `since` filtering; it never
seeds two residents, so the leak passes CI. Fixing this means adding a `residentSub` partition to the event
store key, threading it through `putIfAbsent`/`listOrdered`, resolving it in the webhook the same way push
resolution does, and adding the missing isolation test.

### The live caption surface is a placeholder; the styling logic has no consumer

`caption_styling.dart` and `turn_segmentation.dart` (and their identical package copies) encode exactly the
right rules: a partial is whole-fragment provisional with no per-token confidence (FR-5.3), a finalized token
below 0.6 is de-emphasized and at or above 0.6 is normal (FR-5.3a, 0.6 inclusive), and a session that ends
mid-utterance keeps the trailing turn provisional with null confidence (FR-5.7). These are unit-tested. But a
grep across `app/lib` shows `CaptionEmphasis`, `emphasisForToken`, `CaptionTurn`, and `TurnAccumulator` have
zero consumers outside their own files and tests. Both `conversation_screen.dart` and
`captions_only_screen.dart` render a constant string:

```dart
child: const Text(
  'Captions appear here as your visitor speaks.',
  style: TextStyle(color: Colors.white, fontSize: 22, height: 1.3),
),
```

So AT-4's assertion that "partial renders provisional; finalized token below 0.6 renders de-emphasized; at or
above 0.6 renders normal" is verified only against the pure function, never against a rendered widget. The
same is true for the on-device engine (`FixtureAsrEngine`), which no controller drives. This is the single
biggest gap: the defining accessibility surface of the product has logic and tests but no UI behind it.

### Accessibility invariants leak outside the Settings screen

`contrast.dart` correctly enforces a 4.5:1 floor (the binary search always lands on an extreme that meets the
floor, and the narrow gray band still clears 4.5:1), and `settings_state.dart` runs `enforceContrastFloor` in
its constructor so no stored setting can breach it. `SettingsScreen` also clamps `MediaQuery.textScaler` to
`maxScaleFactor: 2.0`. The problem is scope: the clamp and the floor apply only where they are written. The
conversation and Captions-Only screens neither wrap their subtree in a clamped `MediaQuery` nor read
`captionScale`/`captionForeground` from settings; their caption text is a hardcoded style. NFR-2 requires
dynamic type to 200% on every screen and the contrast floor to hold on rendered captions, and AT-9 gates the
build on it. Because captions are a placeholder string, the widget tests pass without exercising either
invariant on the surface that matters.

### Reply pipeline: fixed set works, contextual suggestions and gap marking do not

`ReplyController` drives the design §5.3 lifecycle correctly for the fixed path: synthesize with a single TTS
retry, degrade the sticky `OutboundModeMachine` to Captions-Only on injection failure (FR-6.4b), append the
resident turn on success (FR-6.5), and block resubmission while speaking (FR-6.3). Two behaviors are missing
their wiring. First, `ReplyBar` takes `contextualSuggestions` as a constructor argument, but nothing in
`app/lib` computes it - not `/replies` for Clarity and not `onDeviceSuggestions` for Privacy - so the FR-7.1a
requirement that Privacy Mode produce suggestions on-device from the safe set plus local templates has no
caller. Second, the echo gate's gap marking is inert in production: `send()` calls
`_echoGate?.onReplyPlaybackStart()` and `onReplyPlaybackEnd()` back-to-back in the same tick and never calls
`settle()`, so the FR-5.6/AT-18 "mark the gated interval in the transcript as a non-visitor gap" is only ever
observed by unit tests calling the gate directly.

### Backend correctness nits that the tests do not surface

`AsrRelay.reconnect` pulls `this.buffer.replay(...)` and pushes it to the new stream but never calls
`this.buffer.clear()`. With `MAX_RECONNECTS = 1` a second drop closes the socket instead of replaying again,
so it cannot bite today, but if the reconnect budget is ever raised the same 2 seconds of audio would be
replayed twice. `deriveResidentSub` in `oauth.ts` derives identity by string-stripping the fixture token
prefixes, which collides: an account whose Ring code is `account-42` and a different account whose code is
`refresh-account-42` both resolve to `resident-account-42` (reproduced). The code is honest that the real
adapter should call Ring's identity endpoint, but deriving a user identity from a bearer token by regex is a
pattern worth removing before it reaches staging.

### Composition and hygiene

`main.dart` still renders `_PlaceholderHome` and instructs the reader to run the spike first; there is no
`ProviderScope` and no place that assembles `SessionController`, `ReplyController`,
`RecordingNoticeController`, `ModelProvisioningMachine`, and the connectivity/permission controllers into a
running flow. `app/lib/reply/audio_spike.dart` is still present although `reply/` already contains the
promoted `ReplyPort` and `ReplyController`; `structure.md` says to delete the spike once the approach is
promoted. Neither is a defect in isolated logic, but together they explain why so many acceptance tests are
satisfied by fixtures rather than by an integrated path: the product is a set of correct parts that have not
been connected.

</details>

<details>
<summary>File map</summary>

Reviewed all changed source. Highlights:

- `backend/src/routes/events.ts`, `backend/src/services/stores.ts`,
  `backend/src/services/fixtures/memory-stores.ts` - event feed with no resident scoping (leak).
- `backend/src/routes/transcripts.ts`, `backend/src/services/transcript-service.ts` - correct resident
  scoping and 403 on foreign residentSub (reference model).
- `backend/src/routes/oauth.ts` - `deriveResidentSub` collides across accounts (fixture-only derivation).
- `backend/src/routes/asr.ts` - replay buffer not cleared after reconnect replay.
- `backend/src/security/*`, `backend/src/services/ring-token-service.ts`,
  `backend/src/services/rate-limiter.ts`, `backend/src/services/webhook-service.ts` - solid; no findings.
- `app/lib/captions/caption_styling.dart`, `turn_segmentation.dart`, `asr_engine.dart` - unit-tested logic,
  no production consumer.
- `app/lib/session/conversation_screen.dart`, `captions_only_screen.dart` - placeholder caption text; no
  textScaler clamp or contrast-floor wiring.
- `app/lib/reply/reply_controller.dart`, `reply_bar.dart`, `ondevice_suggestions.dart`, `echo_gate.dart` -
  fixed path wired; contextual suggestions and gap marking unwired.
- `app/lib/main.dart` - skeleton; no composition root. `app/lib/reply/audio_spike.dart` - undeleted spike.
- `app/lib/settings/*`, `app/lib/consent/*`, `app/lib/permissions/*`, `app/lib/connectivity/*`,
  `app/lib/vision/*`, `app/lib/perf/*`, `app/lib/alerts/*` - reviewed; logic and tests present, wiring absent
  where noted.
- `packages/flutter_ring_captions/lib/**` - clean extraction; logic matches the app copies.

Full diff: `git diff main` on `feat/device-tier-ui-and-a11y`.

</details>
