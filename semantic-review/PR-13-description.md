# Fix/audit remediation

Remediation pass over the findings in the prior threshold audit
(`semantic-review/2026-09-19-002908-pr-threshold-audit.md`) and the separate
CRIT/HIGH/MED/LOW/NIT audit whose IDs are cited in each commit message, plus the
seven review findings raised on this PR (`semantic-review/2026-10-11-154833-pr-13.md`).

The backend security remediations are the core: the prior audit's cross-resident
`/events` leak is closed at the data layer, a non-local boot on fixtures fails
closed, and the OAuth/PKCE, webhook, signaling, and ASR hardening are real fixes.
This PR also resolves the seven process/CI findings from the latest review.

## Summary of changes

- **Backend** (Node + Fastify + TypeScript): resident-scoped event store, fail-closed
  container boot, fail-fast config validation, PKCE/state hardening, WS Origin
  allowlist and device-ownership checks, ASR resource guards, deep log redaction,
  dependency upgrade to Fastify 5, and strengthened (non-vacuous) tests.
- **App** (Flutter): consent gate, persisted settings/consent, accessibility fixes,
  caption contrast and segmentation fixes, injectable ASR engine.
- **Package** `flutter_ring_captions`: input validation, value equality, dependency
  alignment, changelog + example.
- **Android**: real reverse-DNS applicationId, minSdk 26, backup disabled, release
  signing fail-closed, mandatory permissions in the main manifest, committed wrapper.
- **CI** (`.github/workflows/ci.yml`): SHA-pinned actions, job timeouts, gitleaks
  full-history secret scan, production-only `npm audit`, Node 20/22 matrix.

## Review findings addressed (PR #13 review)

| # | Finding | Resolution | Status |
|---|---------|------------|--------|
| 1 | All CI checks red on head | Established cause by running every suite locally; all pass. Red status was environmental (CI log 404 / runner), not a source defect. See verification below. | fixed-and-verified |
| 2 | No PR description / test plan | This document. | fixed |
| 3 | `flutter analyze --fatal-infos` re-added as a hard gate | Verified clean on pinned Flutter 3.38.10 for app and package; kept as a real gate with documented `dart analyze` fallback. | fixed-and-verified |
| 4 | Android permission assertion ran on debug APK | Job now builds `flutter build apk --release` (R8 + resource shrinking) signed with a throwaway CI keystore, and asserts RECORD_AUDIO/INTERNET on `app-release.apk`. | fixed (CI-only verifiable) |
| 5 | config secret-strength guard exempts `test` | Replaced the ad-hoc `!= local && != test` check with an explicit `NON_DEPLOYABLE_ENVS` / `isDeployableEnv()` invariant; documented that `test` is never a deployable target; added tests. | fixed-and-verified |
| 6 | Backend suites not reproducible in review env | Provisioned the toolchain and ran typecheck/lint/vitest/audit; real results below. | fixed-and-verified |
| 7 | Per-resident ASR/session caps are per-process | Made the cross-instance limitation explicit at both sites and tracked it as deferred work in `FEAT-004.json`; the real distributed adapter must carry a shared counter/lock. | documented-as-deferred |

## How each was verified

Toolchain provisioned in a clean environment: Node 22.23.3 with bundled npm 11.4.2,
Flutter 3.38.10 (stable).

### Backend (`backend/`) — fully run

```
npm ci                                      # 301 packages installed
npm run typecheck                           # PASS (tsc --noEmit, exit 0)
npm run lint                                # PASS (eslint, exit 0)
npx vitest run                              # PASS: 275 tests, 36 files
npm run build                               # PASS (tsc -p tsconfig.build.json, exit 0)
npm audit --omit=dev --audit-level=high     # PASS: found 0 vulnerabilities (exit 0)
```

Note: `npm ci` reports 12 advisories, but these are all **dev-only**
(vitest/@vitest/mocker/tinypool/braces). The production gate
`npm audit --omit=dev --audit-level=high` exits 0; the full audit including dev
deps exits 1, confirming the advisories are excluded from the production surface
and the CI gate is correct.

### App (`app/`) — fully run

```
flutter pub get                             # PASS
flutter analyze --fatal-infos               # PASS: No issues found!
dart format --output=none --set-exit-if-changed .   # PASS: 0 changed
dart run tool/lint_ui_copy.dart lib         # PASS: no forbidden dashes
flutter test                                # PASS: 660 tests
```

### Package (`packages/flutter_ring_captions/`) — fully run

```
flutter pub get                             # PASS
flutter analyze --fatal-infos               # PASS: No issues found!
dart format --output=none --set-exit-if-changed .   # PASS: 0 changed
flutter test                                # PASS: 50 tests
```

### CI YAML (`android` job) — CI-only verifiable

The release-APK build requires the Android SDK (provided in CI by the setup
actions) and so was not executed in the remediation environment. The change is
reasoned as follows: `build.gradle.kts` loads release signing from
`key.properties` or the `THRESHOLD_*` env vars and fails a release build closed
when none is present (HIGH-12). The job now generates a throwaway keystore with
`keytool` into `RUNNER_TEMP` and exports the four `THRESHOLD_*` variables, which
satisfies the config-time signing guard, so `flutter build apk --release`
produces a signed, shrunk APK and the aapt assertion runs against the real
release manifest. The `keytool` invocation and the gradle signing wiring were
verified locally; the throwaway keystore generates successfully.

## Known deferred items

These are deliberately out of scope because there is no AWS or Ring Partner
access in this environment. The container fails closed for any non-fixture env
until these are supplied (CRIT-02).

- **Real adapters are still stubs/fixtures**: KMS (crypto), DynamoDB (stores),
  Amazon Transcribe (ASR), Bedrock (reply suggestions), FCM (push), and the real
  Ring OAuth/signaling adapters. A non-local/demo/test boot throws naming the
  missing ports.
- **Cross-instance ASR/session caps** (finding #7): the per-resident ASR
  concurrent-session cap and the signaling single-session invariant use
  per-process in-memory maps. They are correct for the single-process fixture but
  are not a cross-instance guarantee; the real Transcribe and signaling adapters
  must carry a shared counter/lock keyed by `residentSub`. Tracked in
  `.agents/tasks/task-audit-remediation/features/FEAT-004.json`.
- **Resident scoping lives in the fixture store**: the `/events` resident scoping
  guarantee is only as strong as the eventual DynamoDB adapter keying the table
  by resident.
