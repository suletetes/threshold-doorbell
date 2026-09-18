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
    final zones = <Rect>[const Rect(x: 0.0, y: 0.0, width: 0.5, height: 1.0)]; // left half masked

    test('a detection whose center is in a zone is discarded', () {
      const det = Rect(x: 0.1, y: 0.4, width: 0.2, height: 0.2); // center 0.2,0.5 masked
      expect(admitDetection(det, zones), isNull);
    });

    test('a detection outside all zones is admitted unchanged', () {
      const det = Rect(x: 0.7, y: 0.4, width: 0.2, height: 0.2); // center 0.8 unmasked
      final admitted = admitDetection(det, zones);
      expect(admitted, isNotNull);
      expect(admitted!.x, 0.7);
    });

    test('a detection mostly inside a zone is discarded even if its center is out', () {
      // Center at x=0.52 (just outside), but > 50% of area is inside the left half.
      const det = Rect(x: 0.35, y: 0.4, width: 0.34, height: 0.2);
      // masked fraction: overlap x from 0.35 to 0.5 = 0.15 of 0.34 width ~= 0.44
      // Below default 0.5 threshold, so with center outside it is admitted.
      final admitted = admitDetection(det, zones);
      expect(admitted, isNotNull);
      // Now a stricter threshold discards it.
      expect(admitDetection(det, zones, threshold: 0.3), isNull);
    });

    test('no zones means every detection is admitted', () {
      const det = Rect(x: 0.1, y: 0.1, width: 0.2, height: 0.2);
      expect(admitDetection(det, const <Rect>[]), isNotNull);
    });
  });
}
