# Friction log: Threshold

A running log of friction encountered while building Threshold, kept
continuously for the hackathon submission (task 30). Each entry records what got
in the way, how it was resolved, and what it implies for the product or the
Ring / AWS developer experience. Newest entries first.

## Build, environment, and platform friction (Ring + AWS + Flutter/Android)

These are the entries most useful to the Amazon, Ring, and AWS developer-
experience teams: real, specific things that got in the way of getting a working
build and a working Ring integration, with what we expected, what actually
happened, and a concrete suggestion. Severity is our own build-impact rating.

### `flutter analyze` hit "Too many open files" until the ulimit was raised

- **Task attempted:** Run `flutter analyze` as the static-analysis gate in the
  build sandbox.
- **Expected vs actual:** Expected a clean analyzer pass. Initially the Dart
  analysis server hit the process file-descriptor limit and crashed before it
  could finish. After raising the descriptor limit it runs clean and reports
  "No issues found!".
- **Severity:** Medium (a one-time environment fix, not a build blocker).
- **Resolution:** Raise the descriptor limit with `ulimit -n 65536` in the shell
  preamble. With that in place `flutter analyze --fatal-infos` completes and is
  now a hard CI gate for both the app and the package, alongside
  `dart format --set-exit-if-changed .` and `flutter test`.
- **Actionable suggestion:** The Flutter analysis server should cap or pool its
  open file descriptors, or fail with a clear "raise your ulimit" message
  instead of an opaque crash. A one-line note in the Flutter tooling docs about
  `ulimit -n` in constrained/CI environments would save a lot of time.

### The app had no `android/` directory, so it never built

- **Task attempted:** Build the Android APK for a Flutter app that had been
  developed as `lib/`-only.
- **Expected vs actual:** Expected `flutter build apk` to work. Actual: with no
  `android/` platform directory, there was nothing to assemble; the build could
  not produce an APK at all.
- **Severity:** High (no buildable artifact until fixed).
- **Workaround:** Generate the Android platform scaffolding
  (`flutter create --platforms=android .` in the app), then re-apply the
  project-specific Gradle config (desugaring, shrinking, keep rules) on top.
- **Actionable suggestion:** `flutter build apk` should fail with an explicit
  "no android/ directory found, run flutter create --platforms=android" message
  rather than a generic Gradle error, so the missing-scaffold case is obvious.

### `flutter_local_notifications` needs core library desugaring

- **Task attempted:** Build with `flutter_local_notifications` for visitor
  alerts.
- **Expected vs actual:** Expected a plain build. Actual: the plugin uses
  `java.time` APIs that are not available on older Android API levels, so the
  build fails until core library desugaring is enabled.
- **Severity:** Medium (hard build failure, well-documented fix).
- **Workaround:** Set `isCoreLibraryDesugaringEnabled = true` in
  `compileOptions` and add
  `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")`.
- **Actionable suggestion:** The plugin README should state the exact desugaring
  snippet and the `desugar_jdk_libs` version near the top of the Android setup,
  because the underlying build error does not name desugaring as the cause.

### `flutter_webrtc` has no Insertable Streams, forcing a WebView audio path

- **Task attempted:** Inject synthesised reply audio into the outbound half of
  Ring's `sendrecv` WebRTC track (the core feature: the doorbell speaking).
- **Expected vs actual:** Expected to feed generated PCM into a custom outbound
  audio track. Actual: the Flutter WebRTC plugin does not expose the Insertable
  Streams API that the web platform uses for exactly this, and pushing PCM into a
  native track directly was not a reliable path.
- **Severity:** Critical (this is the feature the whole product is built on).
- **Workaround:** Run the audio pipeline inside an in-app WebView, where the
  browser `AudioContext` to `MediaStreamTrack` injection path is well-trodden,
  and drive the outbound track from there (the ARCH-1 decision). We spiked this
  before building any UI so the architecture was de-risked first.
- **Actionable suggestion:** flutter_webrtc exposing an Insertable Streams or
  custom-audio-source API would remove the need for a WebView shim entirely.
  Ring's sample only renders inbound audio, so a short official note that the
  channel is `sendrecv` and how to send into it would help every team that wants
  two-way talk.

### Ring testing needs a Protection subscription and a short-lived Playground token

- **Task attempted:** Exercise the Ring Partner API (devices, live view, events)
  against real infrastructure.
- **Expected vs actual:** Expected to authenticate and call the API. Actual:
  full testing requires a Ring account with an active Ring Protection
  subscription, and the Playground token that lets you work without that expires
  quickly (roughly half an hour), so long sessions keep dropping mid-task.
- **Severity:** Medium (gates real-device testing; the hackathon demo path is
  unaffected).
- **Workaround:** Do API-shape and integration work against the Playground token
  and staging users, budget the Protection subscription up front, and structure
  work so a token refresh does not lose progress. Be honest in the pitch that a
  shipping product needs certification plus a subscription.
- **Actionable suggestion:** A longer-lived development token, or a clear
  in-console countdown of remaining token lifetime, would cut a lot of
  re-authentication churn during a build sprint.

### Java 25 breaks Gradle

- **Task attempted:** Run the Android Gradle build on whatever JDK the
  environment defaulted to.
- **Expected vs actual:** Expected Gradle to run. Actual: on Java 25 the Gradle
  build fails outright; the Android Gradle Plugin toolchain in use does not
  support that JDK.
- **Severity:** High (no Android build at all until the JDK is pinned).
- **Workaround:** Pin the toolchain to Java 21 (`JAVA_HOME="$(mise where
  java@21)"` in the shell preamble) for every Gradle invocation.
- **Actionable suggestion:** The build should fail fast with an explicit
  "unsupported JDK, use Java 17 or 21" message. Documenting the supported JDK
  range prominently in the Flutter/AGP Android setup would prevent the confusing
  downstream Gradle errors a too-new JDK produces.

## Backend signaling, ASR, and infrastructure (this delegation)

- **`flutter analyze` needs a raised file-descriptor limit in the sandbox.**
  The Dart analysis server hit the process file-descriptor limit on its first
  run and could not complete. Resolution: raise it with `ulimit -n 65536`; after
  that `flutter analyze --fatal-infos` runs clean. CI now runs analyze and
  `dart format --set-exit-if-changed .` as hard gates in both Dart jobs, on top
  of `flutter test`. Implication: analyze is a reliable gate here once the
  descriptor limit is raised, so it is no longer skipped.

- **WebSocket close-code propagation over the in-process test transport.**
  `@fastify/websocket`'s `injectWS` uses paired in-memory streams. A client
  `ws.close()` did not reliably surface a server-side `close` event within a
  test tick, so a release-on-disconnect assertion flaked. Resolution: assert the
  server-initiated close path directly (an explicit `end` frame) and use
  `terminate()` plus a bounded poll for the disconnect path. Implication: test
  WS lifecycle through both a client-initiated and a server-initiated close, and
  observe server effects by polling a fixture rather than racing an event.

- **Unauthorized WS handshake races the test listener.** Closing a WS
  synchronously in the upgrade handler (before `injectWS` resolves) meant the
  error frame was gone before the test attached a listener. Resolution: defer the
  unauthorized error-frame-then-close by one `setImmediate` so a just-connected
  client sees the 4401 frame. Implication: any "reject on connect" WS path should
  give the client a tick to attach handlers before sending a final frame.

- **Reconnect-with-replay ordering.** The ASR relay opens the Transcribe stream
  asynchronously on `start`, but audio frames can arrive before the stream is
  ready. Resolution: serialize control-frame handling and buffer early audio,
  flushing it once the stream opens, and keep a 2 second bounded replay buffer
  for reconnects. Implication: a streaming relay must treat "audio before the
  upstream is ready" as a normal case, not an error.

- **Redaction is easy to regress silently.** The pino allowlist is a plain
  string list; a removed path would silently start leaking. Resolution: a logger
  test writes to a capturing destination and asserts the plaintext of tokens,
  PII, transcript text, and bodies never appears in the output, plus a guard that
  the critical key families remain in the allowlist. Implication: prove redaction
  by asserting on serialized output, not by trusting the config.

## Earlier entries (from prior delegations)

- **Ring's bidirectional audio is underused.** Amazon's own Ring sample uses only
  the inbound half of the `sendrecv` WebRTC channel. The defining capability of
  Threshold (a spoken reply at the door) depends on the outbound half, which
  needed a spike to de-risk before any UI work. This shaped the whole task order:
  prove outbound audio first (task 2), build everything else after.

- **No em-dash or en-dash in any user-facing string.** A firm product rule for
  screen-reader consistency. Friction: it is easy to introduce a dash through
  generated copy (Bedrock suggestions) or a stray keystroke. Resolution: a shared
  lint engine used by both a unit test and a CLI, wired into CI as a hard gate
  (AT-24), plus a `stripDashes` step in the reply-rendering path.
