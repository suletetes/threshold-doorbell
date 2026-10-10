import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/vision/privacy_zone_geometry.dart';
import 'package:threshold/vision/vision_port.dart';

void main() {
  final zones = <Rect>[
    const Rect(x: 0.0, y: 0.0, width: 0.5, height: 1.0)
  ]; // left half masked

  VisionCue person(double x, {double conf = 0.9}) => VisionCue(
      kind: CueKind.person,
      box: Rect(x: x, y: 0.4, width: 0.15, height: 0.2),
      confidence: conf);
  VisionCue pkg(double x, {double conf = 0.9}) => VisionCue(
      kind: CueKind.package,
      box: Rect(x: x, y: 0.4, width: 0.15, height: 0.2),
      confidence: conf);

  group('admittedCues (Task 19, FR-11.1)', () {
    test('drops detections centered in a privacy zone', () {
      final frame = VisionFrame(<VisionCue>[person(0.05), person(0.7)]);
      final admitted = admittedCues(frame, zones);
      expect(admitted.length, 1);
      expect(admitted.single.box.x, 0.7);
    });

    test('keeps all detections when there are no zones', () {
      final frame = VisionFrame(<VisionCue>[person(0.05), pkg(0.1)]);
      expect(admittedCues(frame, const <Rect>[]).length, 2);
    });
  });

  group('visualPersonPresent (Task 19 feeds FR-5.4 presence)', () {
    test('true when an admitted person cue is confident enough', () {
      final frame = VisionFrame(<VisionCue>[person(0.7, conf: 0.8)]);
      expect(visualPersonPresent(frame, zones), isTrue);
    });

    test('false when the only person is inside a privacy zone (FR-11.1)', () {
      final frame = VisionFrame(<VisionCue>[person(0.05, conf: 0.99)]);
      expect(visualPersonPresent(frame, zones), isFalse);
    });

    test('false when the person cue is below the confidence floor', () {
      final frame = VisionFrame(<VisionCue>[person(0.7, conf: 0.2)]);
      expect(visualPersonPresent(frame, zones), isFalse);
    });

    test('a package alone is not a person presence', () {
      final frame = VisionFrame(<VisionCue>[pkg(0.7)]);
      expect(visualPersonPresent(frame, zones), isFalse);
      expect(visualPackagePresent(frame, zones), isTrue);
    });
  });

  group('FixtureVision zero-egress (Task 19, FR-11.2)', () {
    test('delivers frames to a local subscriber while transmitting none',
        () async {
      final v = FixtureVision();
      final received = <VisionFrame>[];
      final sub = v.frames.listen(received.add);
      v.emit(VisionFrame(<VisionCue>[person(0.7)]));
      v.emit(VisionFrame(<VisionCue>[pkg(0.6)]));
      // Let the broadcast stream deliver.
      await Future<void>.delayed(Duration.zero);

      // The frames really flowed to an on-device subscriber (locks the LOW-02
      // broadcast behavior) and were recorded locally...
      expect(received.length, 2);
      expect(v.pushed.length, 2);
      // ...but nothing was transmitted. If emit() started counting delivered
      // frames as transmitted (an egress regression), this would fail.
      expect(v.framesTransmitted, 0);
      expect(
        v.framesTransmitted,
        lessThan(v.pushed.length),
        reason: 'frames are processed on-device but never transmitted',
      );
      await sub.cancel();
      await v.dispose();
    });

    test('reports availability so presence can fall back to events (FR-5.4)',
        () {
      expect(FixtureVision().isAvailable, isTrue);
      expect(FixtureVision(available: false).isAvailable, isFalse);
    });
  });
}
