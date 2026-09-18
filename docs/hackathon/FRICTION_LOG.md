# Friction log: Threshold

A running log of friction encountered while building Threshold, kept
continuously for the hackathon submission (task 30). Each entry records what got
in the way, how it was resolved, and what it implies for the product or the
Ring / AWS developer experience. Newest entries first.

## Backend signaling, ASR, and infrastructure (this delegation)

- **`flutter analyze` crashes in the build sandbox.** The Dart analysis server
  hits a bug under the sandbox and cannot complete. Resolution: use
  `flutter test` as the compile-and-correctness gate; it compiles all Dart and
  runs the full unit suite. The CI workflow deliberately omits `flutter analyze`
  for this reason and documents why inline. Implication: for reproducible CI,
  `flutter test` is a sufficient and more reliable gate than `analyze` in
  constrained environments.

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
