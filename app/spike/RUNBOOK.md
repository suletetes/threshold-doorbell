# Task 2 Runbook: the ARCH-1 outbound-audio spike

This is the single go/no-go gate for Threshold. It proves (or disproves) that a synthesized voice can be
injected into the outbound audio track of a Ring WebRTC session, from inside a WebView, and reach the
doorbell. Run it before building any WebRTC or reply UI (tasks 12, 14, 15, 17).

## Why it exists

design.md ARCH-1: only the browser runtime can inject an outbound track (`AudioContext` ->
`MediaStreamAudioDestinationNode` -> `RTCRtpSender.replaceTrack`); `flutter_webrtc` cannot (no Insertable
Streams). If this spike passes, the two-way product is buildable. If it fails, the product ships as
Captions-Only (FR-12) and that decision is made here, in week one, not week five.

## What is verifiable where

- **In CI / this sandbox (no device):** the bridge-message parsing and sticky-verdict logic, via
  `flutter test test/reply/audio_spike_test.dart`. These pass now.
- **In a plain desktop browser (no Ring):** the offline loopback harness in `webrtc_audio_spike.html`
  exercises the full `AudioContext -> replaceTrack -> getStats` path against a local loopback peer. Open the
  file in Chrome, leave the WHEP field blank, Connect -> Run probe. A PASS here proves the injection
  mechanism works in a browser at all.
- **On a real device with a Ring session (the real gate):** proves it works against the actual Ring WHEP
  endpoint through the Flutter WebView.

## Offline browser check (2 minutes, no hardware)

1. Open `app/spike/webrtc_audio_spike.html` in Chrome (or `python3 -m http.server` then browse to it).
2. Leave the WHEP URL blank.
3. Click **1. Connect session** -> **2. Run capability probe**.
4. Expect: verdict **PASS**, log shows `packetsSent` rising above baseline.
   This confirms the browser can inject an outbound track. It does not yet prove Ring accepts it.

## On-device check against Ring (the real go/no-go)

Prerequisites you provide: a Ring developer account, a Ring Protection subscription, a Playground or
staging OAuth token, and a Ring device (or the Ring simulator). A physical Android/iOS device or a
configured emulator with WebView.

1. Add the device-only WebView dependency:
   ```
   cd app && flutter pub add webview_flutter
   ```
2. Register the spike HTML as an asset in `app/pubspec.yaml`:
   ```yaml
   flutter:
     assets:
       - spike/webrtc_audio_spike.html
   ```
3. Wire the WebView in `lib/reply/audio_spike.dart`: replace `_SpikePlaceholder` with a `WebViewWidget`
   whose controller (a) loads the asset HTML, (b) adds a JavaScript channel **named exactly `SpikeBridge`**,
   and (c) forwards each message to `handleBridgeMessage`. The bridge name must match the HTML
   (`window.SpikeBridge.postMessage`).
4. Set `home: const AudioSpikeScreen()` and `flutter run` on the device.
5. Obtain the WHEP endpoint URL (from the backend `/signaling` broker, or directly from the Ring Playground
   for a quick check) and paste it into the WHEP field.
6. Tap **Connect** -> **Run probe**. The probe emits only near-silent audio (<= -60 dBFS), so nothing is
   audible at the door during the test.
7. **PASS**: the banner turns green ("Outbound audio works. ARCH-1 holds."). Then tap **Speak test phrase**
   and confirm it is clearly audible at the doorbell.
8. **FAIL**: the banner turns red. Try the two approved fallbacks in order:
   - Native platform-channel PCM source feeding the outbound track (design §2 alternative).
   - If neither works, adopt Captions-Only (FR-12) as the shipping scope.

## The decision this gates

| Probe result | Action |
|---|---|
| PASS on device against Ring | Build the two-way product (tasks 7, 8, 12, 14, 15). Full demo is viable. |
| PASS in browser, FAIL on device | Investigate the WebView WebRTC support on the target OS version; try the native PCM fallback before giving up. |
| FAIL everywhere | Ship Captions-Only (FR-12). The product is still novel and demoable; only spoken replies are dropped. |

Record the outcome in `.kiro/specs/threshold-doorbell/requirements.md` §7 (Known open items) with the date
and the device tested.
