# Threshold: Aggressive Codebase Audit

Full-repository engineering and security audit of `suletetes/threshold-doorbell` at branch `main`
(HEAD `8992744`, which already contains the merged audit-remediation PR #13 and its follow-ups).
Every finding cites real files and line references read directly from the source. This document is a
companion to the existing `AGGRESSIVE_UI_UX_AUDIT.md` (visual/UX only) and the `semantic-review/`
PR reviews; it does not repeat them except where a prior item is still open or only partially fixed.

Scope read in full: all of `backend/src/**` and representative `backend/test/**`; all of `app/lib/**`
(session, reply, captions, consent, a11y, alerts, perf, vision, settings, design, app) and the Android
build/manifest config; all of `packages/flutter_ring_captions/lib/**`; `.github/workflows/ci.yml`;
`.kiro/specs/**` and `.kiro/steering/**`; `README.md`; and the prior audit artifacts.

---

## 1. Executive summary

**Overall: this is a strong, unusually disciplined codebase for its stage.** It has been through at
least two prior audit rounds (a CRIT/HIGH/MED/LOW/NIT catalogue and PR #13), and most of the serious
problems a first-pass audit would raise are already fixed and regression-tested: the cross-resident
`/events` leak is closed at the data layer, OAuth uses PKCE with a server-side verifier and a
browser-bound state cookie, webhooks verify a timestamped constant-time HMAC with a replay window,
WebSocket upgrades refuse the token in the URL and enforce an Origin allowlist, Ring tokens are
envelope-encrypted with per-purpose HKDF keys, logs are recursively redacted, and the non-fixture
boot path fails closed. The Flutter side is ports-and-adapters throughout with ~275 backend tests and
60 app test files, and the production device adapters fail loudly rather than faking behavior.

The findings below are therefore mostly at the **edges the prior rounds did not reach**, plus a small
number of **design-contract gaps** and **documentation drift**. The two most important are new:

1. **(High) WebSocket routes bypass the post-erasure session revocation.** The erasure revocation
   guard (HIGH-23) is only applied on HTTP routes; `/signaling` and `/asr/stream` never consult it, so
   after `DELETE /me/data` a still-valid bearer can open live Ring sessions and bill Transcribe for up
   to the 30-minute session lifetime.
2. **(Medium) The OAuth deep-link handoff has no Android receiver.** The backend redirects to
   `threshold://auth/complete`, but the Android manifest declares no matching intent-filter and the app
   has no deep-link handling, so the one-time app auth code cannot reach the native app.

Everything else is Medium or below. There are no Critical findings in the current `main`.

**Important environment constraint affecting verification:** `npm`/`node`, `dart`, and `flutter` are
**not installed** in this audit environment, so the backend (vitest/tsc/eslint) and app
(`flutter analyze`/`flutter test`) suites could **not** be run. All findings are from static reading of
the source, consistent with how `semantic-review/2026-10-11-154833-pr-13.md` was produced. CI remains
the authoritative dynamic gate.

**Product-reality caveat (not a defect, but it bounds every finding):** by design the production
adapters for the live WebView session, TTS reply injection, Ring app launch, backend HTTP/WS, data
erasure, and re-auth all `throw DeviceBindingUnavailable` (`app/lib/app/production_adapters.dart`), and
the backend wires in-memory fixtures in every bootable environment (`backend/src/container.ts`). The
app and backend are a fully tested *product-logic shell*; no real Ring/AWS/KMS/DynamoDB/FCM adapter is
implemented. This is honestly documented in `README.md` "Status" and in the FEAT-004 deferral notes.
Several findings below are therefore about correctness of the eventual real path.

### Findings by severity

| Severity | Count | Headline items |
|---|---|---|
| Critical | 0 | none in current `main` |
| High | 2 | WS erasure-revocation bypass; OAuth deep-link has no Android receiver |
| Medium | 6 | no Fastify route schemas (dead validation branch); unbounded request field sizes; distributed caps still per-process; readiness probe is shallow; `.env.example` ships weak defaults and omits new knobs; metrics instrumentation partly unwired |
| Low | 7 | HSTS/secure flag edge cases; `thumbnail_url` allowlist breadth; webhook timestamp requirement vs. real Ring; `expiresAt` NaN handling; unmapped-event retention; privacy-zone subtraction overlap; package `publish_to: none` vs. "ships as MIT package" |
| Info / Observations | several | test coverage shape, deferred adapters, spec drift |

---

## 2. High severity

### H-1. WebSocket routes do not enforce post-erasure session revocation (auth bypass on the live paths)

**Files:** `backend/src/security/ws-auth.ts:51-61`, `backend/src/routes/signaling.ts:58`,
`backend/src/routes/asr.ts:78`, versus `backend/src/app.ts:112-120`.

The HTTP session guard performs two checks: it verifies the signed session and then denies any session
issued at or before the erasure cutoff:

```ts
// app.ts (requireSession)
const claims = verifySession(token, container.config.sessionSecret);
if (!claims) throw errors.unauthorized();
// HIGH-23: a session issued before an erasure cutoff is denied
if (await container.sessionInvalidation.isRevoked(claims.sub, claims.iat)) {
  throw errors.unauthorized();
}
```

The two WebSocket routes authenticate through `authenticateWs`, which **only** calls `verifySession`
and never consults `sessionInvalidation`:

```ts
// ws-auth.ts
export function authenticateWs(request, secret, allowedOrigins): SessionClaims | null {
  if (!isOriginAllowed(request, allowedOrigins)) return null;
  return verifySession(extractWsToken(request), secret); // no isRevoked() check
}
```

`DELETE /me/data` revokes sessions via `TranscriptService.eraseAll` ->
`sessionInvalidation.revokeSessionsIssuedBefore` (`transcript-service.ts:279`), and the HTTP guard
honours that immediately. But `/signaling` and `/asr/stream` do not, so a bearer that is still inside
its 30-minute absolute window (`SESSION_ABSOLUTE_MS`, `session.ts`) can, after the user has asked for
all their data to be erased:

- open a live Ring signaling session (`/signaling`), and
- open a Clarity-Mode ASR relay (`/asr/stream`), which bills Amazon Transcribe.

**Impact:** The erasure guarantee that HIGH-23 was created to provide ("a stateless bearer cannot keep
reading/acting for up to 30 minutes after erasure") holds for REST reads but is bypassed on exactly the
two most sensitive, most expensive paths: establishing a live audio/video session to the door and
streaming audio to a cloud ASR. This is a real authorization gap, not a theoretical one.

**Remediation:** Make `authenticateWs` async and have it consult `sessionInvalidation.isRevoked(claims.sub,
claims.iat)` after `verifySession`, returning null when revoked; or add the `isRevoked` check in both WS
route handlers right after `authenticateWs` returns, closing with `4401` when revoked. Add a regression
test that erases a resident, then asserts a pre-erasure bearer is refused on both `/signaling` and
`/asr/stream` (mirroring the existing HTTP erasure test).

### H-2. OAuth deep-link handoff has no Android receiver and no app-side handling

**Files:** `backend/src/routes/oauth.ts:160-170` and `:52-58`, `backend/src/config.ts:131`
(`appDeepLink` default `threshold://auth/complete`), versus
`app/android/app/src/main/AndroidManifest.xml` (only a `LAUNCHER` intent-filter) and all of `app/lib/**`
(no deep-link handling).

The backend OAuth callback mints a one-time app authorization code and redirects the browser to the
app deep link carrying it (`HIGH-18`):

```ts
reply.code(302).header('location', deepLinkWith(config.appDeepLink, { code: appCode })) ...
```

For the native app to receive `threshold://auth/complete?code=...`, Android needs an
`<intent-filter>` with `<data android:scheme="threshold" .../>` and a `BROWSABLE` category, plus code
that reads the initial/incoming link and calls `POST /oauth/exchange`. Neither exists:

- `AndroidManifest.xml` declares exactly one intent-filter, the `MAIN`/`LAUNCHER` one. There is no
  `android:scheme`, no `VIEW`/`BROWSABLE` filter, and no App Links `autoVerify`.
- `grep` across `app/lib/**` finds no `auth/complete`, no `getInitialLink`, no `app_links`/`uni_links`,
  and no deep-link plugin in `pubspec.yaml`.

**Impact:** The server half of the OAuth-to-native-session handoff is implemented and well tested, but
the client half cannot complete: a real device would land on the browser redirect and the code would
never reach the app. The sign-in flow that `README.md` describes as "built" (OAuth with PKCE) is not
end-to-end even in principle on Android. This compounds with the deferred `ProductionAuthPort`
(which throws), so there is no path to an authenticated session on device today.

**Remediation:** Add a `VIEW`/`BROWSABLE` intent-filter for the `threshold` scheme (or, preferably, an
Android App Link with `autoVerify` over HTTPS) to the manifest, add a deep-link plugin and a handler
that extracts `code`/`error` and drives `POST /oauth/exchange`, and wire `ProductionAuthPort` to it.
Track this as part of the deferred device-adapter work, but record it explicitly because the current
README overstates the auth flow as complete.

---

## 3. Medium severity

### M-1. No Fastify route-level JSON schemas, despite the design mandating them; the schema error branch is dead

**Files:** all of `backend/src/routes/*.ts` (no `schema:` option on any route), versus
`.kiro/specs/threshold-doorbell/design.md` §9 ("every route validated against its Fastify JSON schema")
and `.kiro/steering/tech.md` ("Schema-validated routes"); `backend/src/app.ts:134-139` references
`err.validation`.

`grep -rn "schema:" backend/src/routes` returns nothing. Every route reads `request.body`/`request.query`
as `unknown` and hand-validates inside the service layer (e.g. `transcript-service.ts`, `replies.ts`,
`webhook-service.ts`). The design and steering docs explicitly require Fastify JSON Schema validation on
every route, and the contract-test strategy (design §9) is written around it. As a direct consequence,
the error handler's Fastify-validation branch is **dead code**:

```ts
// app.ts: this never fires because no route declares a schema
if ((err as { validation?: unknown }).validation) {
  container.metrics.increment('schema_validation_failure');
  ...
}
```

**Impact:** Not a crash risk (hand-validation plus the 64 KiB body limit covers the obvious cases), but
it is a real divergence from the stated design and a correctness/maintainability risk: validation rules
live in prose inside services rather than in a declarative, contract-testable schema, and the
`schema_validation_failure` metric (design §10) is never incremented for genuine request-shape failures
through this branch. The contract tests described in design §9 cannot be "every route against its schema"
because there are no schemas.

**Remediation:** Add Fastify JSON schemas (`body`, `querystring`, `params`) to each route, or explicitly
amend the design/steering docs to state that validation is service-layer by choice and remove the dead
`err.validation` branch. If schemas are added, the existing service validation becomes defense-in-depth.

### M-2. Request field sizes are unbounded below the 64 KiB body limit (`visitorText`, `turns`)

**Files:** `backend/src/routes/replies.ts:30-33`, `backend/src/services/transcript-service.ts`
(turns array), `backend/src/config.ts:95` (`bodyLimitBytes` 64 KiB). FEAT-004 step E claimed "add JSON
body schemas with maxLength/maxItems"; `grep -rn "maxLength\|maxItems" backend/src` returns nothing.

`/replies` accepts `visitorText` as "any string" with no length cap; `/transcripts` accepts a `turns`
array with no item cap and each `turn.text` with no length cap. The only bound is the global 64 KiB body
limit. A single 64 KiB `visitorText` is still forwarded to the Bedrock adapter in Clarity Mode, and a
64 KiB payload of thousands of tiny turns is accepted into a transcript.

**Impact:** Moderate. 64 KiB caps the worst case, but it allows a ~64 KiB prompt to reach Bedrock (cost
and prompt-injection surface) and large turn arrays into storage, and it is a stated-but-unimplemented
remediation (FEAT-004 marked MED-29 "fixed" via the body limit alone; the schema `maxLength`/`maxItems`
part was not done).

**Remediation:** Add `maxLength` on `visitorText`/`turn.text` and `maxItems` on `turns` (via the M-1
schemas, or as explicit service-layer checks returning `schema`/400). A few KiB for `visitorText` and a
bounded turn count are ample for the product.

### M-3. Per-resident ASR and single-session caps are per-process only (do not hold across instances)

**Files:** `backend/src/routes/asr.ts:70` (`liveByResident` map), `backend/src/services/signaling-service.ts:63`
(`active` map). Documented as deferred in both files and in
`.agents/tasks/task-audit-remediation/features/FEAT-004.json`.

The HIGH-22 concurrent-ASR-session cap and the FR-4.7 single-live-session invariant are enforced with
per-process in-memory maps. The design mandates "stateless backend, >= 2 instances" (design §1, §11), so
across a real multi-pod deployment a resident can hold `asrMaxSessionsPerResident` ASR streams **per
instance** and one live signaling session **per instance**, defeating both guarantees globally.

**Impact:** Correct for the single-process fixture (which is all that runs today), but the invariants the
findings were about do not hold in the intended production topology. This is already acknowledged in code
comments and tracked as deferred; it is listed here so it is not lost when the real adapters land.

**Remediation:** When the Transcribe/signaling adapters are built, carry the counter/lock in a shared
store (atomic DynamoDB/Redis counter or a conditional-write claim row keyed by `residentSub`, with the
session TTL as the lease), as the deferral note already prescribes.

### M-4. Readiness probe is shallow and will mislead once real adapters exist

**File:** `backend/src/app.ts:214-233` (`runReadinessChecks`).

`/ready` checks that `config.env` is a string and that `tokenStore.get('__readiness_probe__')` does not
throw. In fixture mode the token store is in-process, so readiness is effectively liveness. The comment
acknowledges a real adapter "would ping its datastore and token store here," but as written a deployment
with a broken DynamoDB/KMS would still report ready because the fixture store never throws.

**Impact:** Low today (no real adapters), but it is a latent operational hazard: an orchestrator would
route traffic to an instance that cannot actually serve. Flagged because `/ready` exists specifically to
gate traffic and currently cannot do its job for the production path.

**Remediation:** Make the readiness checks adapter-driven (a real datastore/KMS ping) when those adapters
are introduced, and keep the fixture path returning ready. Consider a timeout on each check.

### M-5. `.env.example` ships insecure defaults and omits the newer configuration knobs

**Files:** `backend/.env.example` versus `backend/src/config.ts` (`WEBHOOK_HMAC_KEYS`, `WS_ALLOWED_ORIGINS`,
`BODY_LIMIT_BYTES`, `RATE_LIMIT_MAX`, `RATE_LIMIT_WINDOW_MS`, `WS_MAX_PAYLOAD_BYTES`,
`ASR_MAX_SESSIONS_PER_RESIDENT`, `ASR_MAX_SESSION_MS`, `ASR_OPEN_TIMEOUT_MS`, `ASR_MAX_PENDING_FRAMES`).

`.env.example` still lists only the original variables and the insecure local defaults
(`SESSION_SECRET=local-dev-session-secret-change-me`, `RING_CLIENT_SECRET=local-fixture-secret`,
`WEBHOOK_HMAC_KEY=local-fixture-hmac-key`), and even its comment enumerates `local | staging | demo`
while `config.ts` also supports `test`. None of the rate-limit, WS-origin, HMAC-rotation, or ASR-limit
knobs that `config.ts` now reads are documented.

**Impact:** Documentation drift. The hard `assertStrongSecret` guard (`config.ts`) means a `staging`/`demo`
boot with these defaults fails fast (good), so this is not a deploy-with-weak-secrets risk. But an
operator copying `.env.example` has no discoverable list of the security-relevant knobs (`WS_ALLOWED_ORIGINS`
in particular: empty by default means browser WS clients cannot connect, which is easy to misdiagnose).

**Remediation:** Update `.env.example` to document every variable `config.ts` reads, with safe placeholder
values and a note that staging/demo require real 32+ char secrets. Add `WS_ALLOWED_ORIGINS` guidance.

### M-6. Latency metrics (`observe`) are defined but never recorded on the request paths

**Files:** `backend/src/observability/metrics.ts` (defines `g1a/g1b/g2/g3/webhook_ack_ms` and
`InMemoryMetricsSink.observe`), versus the routes. Only counters are incremented
(`metrics.increment('refresh')` in `oauth.ts`, `'bedrock_fallback'` in `replies.ts`,
`'schema_validation_failure'` in `app.ts`). `grep` shows no `metrics.observe(...)` call anywhere in
`backend/src/routes` or services.

Design §10 lists the latency metrics G1a/G1b/G2/G3 and webhook-ack time as first-class, and FEAT-004
step C said "instrument the request paths with metrics.observe." The `onResponse` hook logs
`responseTimeMs` but does not feed it to `metrics.observe`, and none of the business-latency metrics
(webhook ack, tap-to-audio, open-to-first-caption) are recorded.

**Impact:** The observability contract (design §10) and its alarms (webhook ack over 5 s, etc.) cannot be
satisfied because the timings are never captured. Low operational impact today (no real backend), but it
is a partially-implemented remediation and a gap against the stated design.

**Remediation:** Record `webhook_ack_ms` in the webhook route and the G-series timings where the
corresponding events occur (several are app-side and belong to the latency harness, but the backend ones
should feed `metrics.observe`). Alternatively, scope the design §10 metric list to what is actually wired
and note the rest as app-side.

---

## 4. Low severity

### L-1. HSTS and `secure` cookie flag keyed on `env !== 'local'` rather than on actual TLS

**Files:** `backend/src/app.ts:98-104` (HSTS), `backend/src/routes/oauth.ts:72,159,191,220` (`secure:
config.env !== 'local'`).

Cookies are `secure` and HSTS is sent whenever the env is not `local`. For `test` this is harmless; for a
`staging`/`demo` instance that (misconfigured) terminates plain HTTP, `secure` cookies would silently not
be sent and HSTS would be advertised over HTTP. The design assumes TLS termination outside local, so this
is correct under the intended deployment, but it couples a transport property to an env name.

**Remediation:** Prefer deriving "is this connection secure" from `x-forwarded-proto`/`request.protocol`
where available, or document that all non-local envs are guaranteed TLS at the edge.

### L-2. Thumbnail-URL allowlist includes all of `*.amazonaws.com`

**File:** `backend/src/services/webhook-service.ts:33` (`ALLOWED_THUMBNAIL_HOST_SUFFIXES = ['.ring.com',
'.amazonaws.com']`).

The LOW-29 sanitizer only keeps HTTPS thumbnail URLs on Ring/AWS hosts, which is good. But `.amazonaws.com`
is extremely broad (any S3 bucket, any AWS-hosted site). A webhook that is otherwise HMAC-authenticated is
the only source, so exploitability is low, but the allowlist is wider than "Ring's own CDN."

**Remediation:** Narrow to the specific Ring/S3 bucket host(s) actually used, once known, or document why
the broad suffix is acceptable.

### L-3. Mandatory webhook timestamp may not match real Ring deliveries

**Files:** `backend/src/security/hmac.ts:40-66`, `backend/src/routes/webhook.ts:40-55`.

`verifyTimestampedSignature` rejects any delivery lacking an `x-ring-timestamp` header or outside the
+/-5 minute window. This is a sound anti-replay design, but it assumes real Ring webhooks send a timestamp
header and sign `timestamp.body`. If the real Ring Partner webhook format differs (e.g. no timestamp, or a
different signing scheme), every real delivery would 401. The plain `verifySignature` (body-only) still
exists but is not used by the route.

**Impact:** Only matters when the real Ring integration lands; today the fixture controls the format.
Flagged so the signing contract is validated against Ring's actual webhook spec before go-live.

### L-4. `getAccessToken` treats an unparseable `expiresAt` as "not near expiry"

**File:** `backend/src/services/ring-token-service.ts:66-76`.

`nearExpiry = Number.isFinite(expiresMs) && expiresMs - now <= REFRESH_SKEW_MS`. If a stored record's
`expiresAt` is corrupt/unparseable (`NaN`), `nearExpiry` is false, so the service skips refresh and tries
to decrypt and return the (possibly expired) access token. A corrupt record should probably trigger a
refresh (or `refresh_failed`) rather than being treated as a valid, far-from-expiry token.

**Remediation:** Treat non-finite `expiresMs` as "must refresh" (or as `refresh_failed`).

### L-5. Unmapped webhook events are stored under `__unmapped__` with no erasure owner

**File:** `backend/src/services/webhook-service.ts:120-129` (`UNMAPPED_RESIDENT`),
`memory-stores.ts` (`deleteAllForResident`).

Events for a device not yet mapped to a resident are quarantined under `__unmapped__` (good: not orphaned
under `''`, never pushed). But those rows are never attributable to a real resident and are not removed by
any resident's `DELETE /me/data`. They rely solely on the 7-day event TTL (design §3). If a device is
mapped later, the already-quarantined events are not re-attributed.

**Impact:** Minor data-retention wrinkle; events contain a device id, timestamp, type, and sanitized
thumbnail URL, not transcript text. The 7-day TTL bounds it.

**Remediation:** Either re-attribute `__unmapped__` events on first device mapping, or document that
unmapped events live only until the TTL and are intentionally unerasable per-resident.

### L-6. Privacy-zone rectangle subtraction can double-count overlapping zones

**File:** `app/lib/vision/privacy_zone_geometry.dart:120-170` (`maskBeforeDetection` / `_subtract`).

`maskBeforeDetection` subtracts each zone from the running region set sequentially. For non-overlapping
zones this is correct; for overlapping zones the decomposition can produce overlapping output rectangles
(the comment notes "when zones overlap, the union is removed," which the strip-splitting does not
strictly guarantee without a union step). `maskedFraction` is explicitly a conservative upper bound (safe:
masks more). The admission gate (`admitDetection`) is center-plus-threshold based and is the real safety
net, so masked detections are still discarded.

**Impact:** On-device only, frames never leave the device, and the net effect of any inaccuracy is
*stricter* masking (safe direction). Flagged for correctness, not safety.

**Remediation:** If exact masked geometry ever matters (e.g. feeding a detector only unmasked pixels on
device), use a proper rectangle-union/subtraction; otherwise document the conservative behavior as
intentional.

### L-7. The "open source" package is `publish_to: "none"`

**Files:** `packages/flutter_ring_captions/pubspec.yaml:5` (`publish_to: "none"`), versus `README.md`
("ships as a standalone MIT package" / Open Source mini-challenge).

The package is framed as the deliverable for the Open Source challenge and carries an MIT `LICENSE`, but
`publish_to: "none"` means it cannot be published to pub.dev as written. Its SDK floor
(`sdk: ">=3.8.0"`, `flutter: ">=3.32.0"`) is also notably higher than the app's (`>=3.4.0` / `>=3.24.0`),
which is fine for a standalone package but worth noting as an intentional divergence (documented in the
pubspec comment as LOW-24).

**Remediation:** If pub.dev publication is intended, remove `publish_to: "none"` and complete the pub
metadata; otherwise clarify in the README that the package is "extractable/MIT-licensed" rather than
"published."

---

## 5. Informational observations and positives worth protecting

These are not defects; they are things an aggressive audit should record.

- **Security core is genuinely solid.** PKCE with server-held verifier keyed by a single-use nonce
  (`oauth.ts`, `oauth-txn-store`), browser-bound state via `H(nonce)` cookie, per-purpose HKDF key
  separation (`security/keys.ts`), AES-256-GCM envelope crypto with versioned ciphertext
  (`local-crypto.ts`), constant-time comparisons everywhere, single-flight token refresh
  (`ring-token-service.ts`), recursive log redaction with a key denylist at any depth
  (`observability/logger.ts`), and fail-closed container boot outside fixtures (`container.ts`). Keep all
  of it; do not regress it in a refactor.
- **Resource-exhaustion hardening on the live paths is thorough.** `/asr/stream` bounds pending frames,
  caps session count and duration, races the upstream open against a timeout, and re-checks `disposed`
  after every await (`asr.ts`); WS `maxPayload`, HTTP `bodyLimit`, and `@fastify/rate-limit` are all wired
  (`app.ts`, `config.ts`).
- **The Flutter logic is high quality and well-tested.** The session controller's generation-token guard
  against a stale `open()` resurrecting an ended session (`session_controller.dart` `_openGeneration`),
  the echo-gate timing with an injectable clock (`echo_gate.dart`), the sticky outbound-mode machine, and
  the compliance-fallback resolution after the real probe (`home_screen.dart` `_resolveComplianceAfterProbe`)
  are all careful. The prior "unwired" findings (consent gate, session-start coordinator, caption pump)
  are now genuinely wired through the composition root.
- **The UI-copy dash lint is unusually robust** (`a11y/ui_copy_lint.dart`): it decodes `\uXXXX`/`\u{...}`
  escapes so a forbidden dash cannot be smuggled past the lint, and the reply sanitizer
  (`packages/.../reply_bridge.dart`) strips an extended set of dash-like glyphs and bounds suggestion
  length. This is the accessibility hard-constraint taken seriously.
- **Tests assert behavior, not constants.** Spot-checked `fixture-transcribe.test.ts` (the
  "never persists audio" test now asserts the opposite of its old vacuous version) and the FEAT-004 /
  PR #13 strengthening of `waitFor`, the Privacy/Bedrock test, and the refresh-metric test. No evidence of
  assertions weakened to pass CI.
- **CI is a real gate** (`.github/workflows/ci.yml`): SHA-pinned actions, job timeouts, Node 20/22 matrix,
  `flutter analyze --fatal-infos` restored as a hard gate, the UI-copy dash lint, a gitleaks full-history
  secret scan, a production-only `npm audit`, and (post-PR-#13 follow-up `9249db1`) the Android job now
  builds the **release** APK and asserts `RECORD_AUDIO`/`INTERNET` survive R8/resource shrinking (the
  prior review's "debug APK" objection is resolved).

### Spec/doc drift to reconcile (low effort, high clarity payoff)

- `design.md` §9 vs. reality: route-level JSON schemas (M-1) and the latency metrics (M-6) are specified
  but not implemented. Either implement or amend the spec.
- `design.md` §12 "Known open items: None" is optimistic given the number of deferred real adapters and the
  cross-instance caveats (M-3); consider listing the deferred adapters there as the spec itself requires
  ("Any new ambiguity must be recorded here ... before code depends on it").
- `README.md` describes OAuth as built; H-2 shows the native handoff is not end-to-end on Android.

---

## 6. Methodology and limitations

- **Read, not run.** `flutter`, `dart`, `node`, and `npm` are absent from this environment (verified:
  `flutter: command not found`, `dart: command not found`), so the vitest, tsc, eslint, `flutter analyze`,
  and `flutter test` suites were not executed. Dynamic verification remains CI's job. Findings are from
  reading `backend/src/**` and representative `backend/test/**` in full, all of `app/lib/**`, the Android
  build/manifest config, `packages/flutter_ring_captions/lib/**`, the CI workflow, the specs/steering, and
  the prior audit artifacts.
- **Built on prior rounds.** `main` already contains the merged PR #13 and its follow-up commits. This
  audit deliberately targets what those rounds did not reach (the WS revocation gap, the Android deep-link
  receiver, the route-schema/metrics design gaps) and re-states the deferred items so they are not lost.
- **No source was modified.** This is a report. The two items most worth acting on before any real
  deployment are H-1 (WS erasure-revocation bypass, a true authorization gap in the current code) and H-2
  (OAuth deep-link receiver, which blocks end-to-end sign-in on device).
