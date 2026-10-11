// On-device visual context port (Task 19, FR-11.1, FR-11.2; FR-5.4 presence).
// The live binding runs google_mlkit_object_detection on inbound WebView frames
// entirely on-device (deferred to device); frames never leave the handset
// (FR-11.2). This port abstracts the detector so the privacy-zone filtering and
// the presence-cue model are unit-testable with a fixture that emits scripted
// detections. The fixture also proves the zero-egress property: it exposes a
// framesTransmitted counter that stays zero.

import 'dart:async';

import 'privacy_zone_geometry.dart';

/// A detected object cue. Only person and package cues are modeled (N1: no
/// open-ended vision). Confidence is in [0,1].
enum CueKind { person, package }

class VisionCue {
  const VisionCue(
      {required this.kind, required this.box, required this.confidence});
  final CueKind kind;
  final Rect box;
  final double confidence;
}

/// A single processed frame's raw detections, before privacy-zone filtering.
class VisionFrame {
  const VisionFrame(this.detections);
  final List<VisionCue> detections;
}

/// Source of on-device vision frames. Implementations MUST NOT transmit frames
/// (FR-11.2).
abstract class VisionPort {
  bool get isAvailable;
  Stream<VisionFrame> get frames;
}

/// Deterministic fixture: tests push frames and assert filtering + presence.
/// framesTransmitted stays 0 to prove frames never leave the device (FR-11.2).
class FixtureVision implements VisionPort {
  FixtureVision({this.available = true});

  final bool available;
  int framesTransmitted = 0;
  final List<VisionFrame> pushed = <VisionFrame>[];

  // A broadcast controller so a live subscriber receives frames emitted after
  // it subscribes. The old Stream.fromIterable snapshot replayed only the
  // already-pushed frames, so later frames were missed (LOW-02).
  final StreamController<VisionFrame> _controller =
      StreamController<VisionFrame>.broadcast();

  @override
  bool get isAvailable => available;

  /// Emit a frame. Recorded locally; never transmitted (FR-11.2).
  void emit(VisionFrame frame) {
    pushed.add(frame);
    _controller.add(frame);
  }

  @override
  Stream<VisionFrame> get frames => _controller.stream;

  /// Release the controller (test teardown).
  Future<void> dispose() => _controller.close();
}

/// Filter a frame's detections through the privacy zones (FR-11.1): a detection
/// is kept only if it passes [admitDetection]. Masked detections are discarded
/// so masked pixels never influence any downstream signal.
List<VisionCue> admittedCues(VisionFrame frame, List<Rect> zones,
    {double threshold = 0.5}) {
  final out = <VisionCue>[];
  for (final cue in frame.detections) {
    final admitted = admitDetection(cue.box, zones, threshold: threshold);
    if (admitted != null) out.add(cue);
  }
  return out;
}

/// The on-device presence signal derived from admitted cues (FR-5.4): at least
/// one admitted person cue at or above [minConfidence]. This is the visual half
/// of the FR-5.4 presence definition; the event half is combined in the caption
/// layer.
bool visualPersonPresent(
  VisionFrame frame,
  List<Rect> zones, {
  double minConfidence = 0.5,
  double threshold = 0.5,
}) {
  return admittedCues(frame, zones, threshold: threshold)
      .any((c) => c.kind == CueKind.person && c.confidence >= minConfidence);
}

/// True when at least one admitted package cue is present (context for the UI).
bool visualPackagePresent(
  VisionFrame frame,
  List<Rect> zones, {
  double minConfidence = 0.5,
  double threshold = 0.5,
}) {
  return admittedCues(frame, zones, threshold: threshold)
      .any((c) => c.kind == CueKind.package && c.confidence >= minConfidence);
}
