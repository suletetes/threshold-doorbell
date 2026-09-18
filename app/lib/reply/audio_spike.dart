// ============================================================================
// THE AUDIO SPIKE — do this FIRST, before any UI.
//
// Goal: prove that a synthesised voice can be injected into the OUTBOUND
// WebRTC audio track of a Ring live session and be AUDIBLE AT THE DOOR.
// This is risk R1 in docs/hackathon/threshold-spec.md §9 and the go/no-go for
// the entire product. If it works, we build the real thing. If it does not,
// we fall back to the webview_flutter audio pipeline — and we decide that HERE,
// in week one, not week five.
//
// What to prove, in order:
//   1. Open a Ring WebRTC session with the audio transceiver as `sendrecv`
//      (mirror the sample's useWebRTCStream.ts: audio sendrecv, video recvonly).
//   2. Generate PCM audio locally (start with a test tone, then flutter_tts
//      rendered to a buffer).
//   3. Feed that PCM into a custom outbound audio track on the peer connection.
//   4. Confirm it is audible at the physical/simulated device.
//
// Fallbacks, in order, if step 3 is not achievable directly in flutter_webrtc:
//   (a) run the media/audio pipeline inside an in-app WebView (webview_flutter),
//       where AudioContext -> MediaStreamTrack injection is well-trodden;
//   (b) a platform channel to a thin native module that pushes PCM into the
//       peer connection;
//   (c) degraded demo only: TTS through the phone speaker (last resort).
//
// Never mock this feature — it is the feature judges came to see.
// ============================================================================

// TODO(spike): implement using package:flutter_webrtc.
// Keep this file dependency-light and throwaway. Once the approach is proven,
// promote the working pieces into lib/ring/ (session) and lib/reply/ (tts).

Future<void> runAudioSpike() async {
  throw UnimplementedError(
    'Audio spike not implemented yet. This is intentionally the first task — '
    'see the header of this file and threshold-spec.md §9 R1.',
  );
}
