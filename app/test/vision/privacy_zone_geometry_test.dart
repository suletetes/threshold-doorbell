import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/vision/privacy_zone_geometry.dart';

void main() {
  group('Rect geometry (Task 19, FR-11.1)', () {
    test('intersection of overlapping rects', () {
      const a = Rect(x: 0, y: 0, width: 0.5, height: 0.5);
      const b = Rect(x: 0.25, y: 0.25, width: 0.5, height: 0.5);
      final i = a.intersection(b);
      expect(i, isNotNull);
      expect(i!.area, closeTo(0.25 * 0.25, 1e-9));
    });

    test('no intersection for disjoint rects', () {
      const a = Rect(x: 0, y: 0, width: 0.2, height: 0.2);
      const b = Rect(x: 0.5, y: 0.5, width: 0.2, height: 0.2);
      expect(a.intersection(b), isNull);
    });

    test('contains checks the center point inclusively', () {
      const z = Rect(x: 0.2, y: 0.2, width: 0.4, height: 0.4);
      expect(z.contains((x: 0.4, y: 0.4)), isTrue);
      expect(z.contains((x: 0.1, y: 0.1)), isFalse);
    });
  });

  group('maskedFraction (Task 19, FR-11.1)', () {
    test('fully masked region is 1.0', () {
      const region = Rect(x: 0.1, y: 0.1, width: 0.2, height: 0.2);
      const zone = Rect(x: 0, y: 0, width: 1, height: 1);
      expect(maskedFraction(region, [zone]), closeTo(1.0, 1e-9));
    });

    test('unmasked region is 0.0', () {
      const region = Rect(x: 0.1, y: 0.1, width: 0.2, height: 0.2);
      const zone = Rect(x: 0.8, y: 0.8, width: 0.1, height: 0.1);
      expect(maskedFraction(region, [zone]), 0);
    });

    test('half-masked region is about 0.5', () {
      const region = Rect(x: 0, y: 0, width: 0.4, height: 0.4);
      const zone = Rect(x: 0, y: 0, width: 0.2, height: 0.4); // left half
      expect(maskedFraction(region, [zone]), closeTo(0.5, 1e-9));
    });
  });

  group('admitDetection (Task 19, FR-11.1 masked pixels never emitted)', () {
    final zones = <Rect>[
      const Rect(x: 0.0, y: 0.0, width: 0.5, height: 1.0)
    ]; // left half masked

    test('a detection whose center is in a zone is discarded', () {
      const det = Rect(
          x: 0.1, y: 0.4, width: 0.2, height: 0.2); // center 0.2,0.5 masked
      expect(admitDetection(det, zones), isNull);
    });

    test('a detection outside all zones is admitted unchanged', () {
      const det =
          Rect(x: 0.7, y: 0.4, width: 0.2, height: 0.2); // center 0.8 unmasked
      final admitted = admitDetection(det, zones);
      expect(admitted, isNotNull);
      expect(admitted!.x, 0.7);
    });

    test(
        'a 44% masked detection with its center out is admitted at the default threshold',
        () {
      // Center at x=0.52 (just outside), with about 44% of its area inside the
      // left half. The test name now matches the assertion (MED-08): at the
      // default 0.5 threshold it is admitted; a stricter threshold discards it.
      const det = Rect(x: 0.35, y: 0.4, width: 0.34, height: 0.2);
      // masked fraction: overlap x from 0.35 to 0.5 = 0.15 of 0.34 width ~= 0.44
      final admitted = admitDetection(det, zones);
      expect(admitted, isNotNull); // 0.44 is below the 0.5 default
      // A stricter threshold (0.3) discards the same detection.
      expect(admitDetection(det, zones, threshold: 0.3), isNull);
    });

    test('no zones means every detection is admitted', () {
      const det = Rect(x: 0.1, y: 0.1, width: 0.2, height: 0.2);
      expect(admitDetection(det, const <Rect>[]), isNotNull);
    });
  });

  group('maskBeforeDetection (MED-08, FR-11.1 mask before inference)', () {
    const frame = Rect(x: 0, y: 0, width: 1, height: 1);

    test('no zones leaves the whole frame', () {
      final regions = maskBeforeDetection(frame, const <Rect>[]);
      expect(regions, hasLength(1));
      expect(regions.single.area, closeTo(1.0, 1e-9));
    });

    test('a left-half zone leaves only the right half for detection', () {
      final zones = <Rect>[const Rect(x: 0, y: 0, width: 0.5, height: 1.0)];
      final regions = maskBeforeDetection(frame, zones);
      // The remaining regions must not overlap the masked zone at all: no
      // masked pixel reaches the detector (mask BEFORE detection).
      for (final r in regions) {
        for (final z in zones) {
          expect(r.intersection(z), isNull,
              reason:
                  'remaining region must not overlap a masked zone (MED-08)');
        }
      }
      // The total remaining area is the unmasked right half.
      final totalArea = regions.fold<double>(0, (sum, r) => sum + r.area);
      expect(totalArea, closeTo(0.5, 1e-9));
    });

    test(
        'a center zone leaves a frame-minus-hole decomposition with no masked pixels',
        () {
      final zones = <Rect>[
        const Rect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
      ];
      final regions = maskBeforeDetection(frame, zones);
      for (final r in regions) {
        expect(r.intersection(zones.single), isNull);
      }
      final totalArea = regions.fold<double>(0, (sum, r) => sum + r.area);
      // Frame area 1.0 minus the 0.25 hole.
      expect(totalArea, closeTo(0.75, 1e-9));
    });
  });
}
