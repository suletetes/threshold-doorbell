// flutter_ring_captions: accessibility-oriented pure logic for live captions and
// a reply bridge on a Ring style video doorbell. Extracted from the Threshold
// project (a two-way captioned doorbell for deaf and hard-of-hearing residents)
// as a standalone MIT package.
//
// This library is intentionally free of device, network, and SDK dependencies:
// it is the decision logic (confidence styling, turn segmentation, sticky
// outbound mode, reply-bar assembly and dash-safe sanitization) that a host app
// wires to its own WebRTC session, ASR engine, and TTS.

library flutter_ring_captions;

export 'src/caption_styling.dart';
export 'src/turn_segmentation.dart';
export 'src/reply_bridge.dart';
export 'src/outbound_mode.dart';
