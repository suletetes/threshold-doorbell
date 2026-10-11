// Privacy-zone geometry (Task 19, FR-11.1, FR-11.2). Pure geometry that excludes
// masked privacy-zone regions from visual processing and guarantees masked
// pixels are never emitted (FR-11.1). All processing is on-device and frames
// never leave the handset (FR-11.2); this file is the region math only and has
// no network path at all. It also decides whether a detected cue is admissible
// (its center must be outside every privacy zone) so masked detections are
// discarded before they can influence presence (FR-5.4).

import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// An axis-aligned rectangle in normalized frame coordinates [0,1]. Mirrors the
/// design.md §3 BoundingBox (x, y, width, height).
@immutable
class Rect {
  const Rect(
      {required this.x,
      required this.y,
      required this.width,
      required this.height});

  final double x;
  final double y;
  final double width;
  final double height;

  double get left => x;
  double get top => y;
  double get right => x + width;
  double get bottom => y + height;
  double get area => math.max(0, width) * math.max(0, height);

  /// The center point of the rectangle.
  ({double x, double y}) get center => (x: x + width / 2, y: y + height / 2);

  /// True when [point] lies inside this rectangle (inclusive of edges).
  bool contains(({double x, double y}) point) =>
      point.x >= left &&
      point.x <= right &&
      point.y >= top &&
      point.y <= bottom;

  /// The overlapping rectangle with [other], or null when they do not overlap.
  Rect? intersection(Rect other) {
    final l = math.max(left, other.left);
    final t = math.max(top, other.top);
    final r = math.min(right, other.right);
    final b = math.min(bottom, other.bottom);
    if (r <= l || b <= t) return null;
    return Rect(x: l, y: t, width: r - l, height: b - t);
  }

  /// True when this rectangle overlaps any of [zones].
  bool overlapsAny(List<Rect> zones) =>
      zones.any((z) => intersection(z) != null);
}

/// The fraction of [region] that is covered by any of the [zones] (0..1). Used
/// to decide how heavily a region is masked.
///
/// This sums each zone's intersection area with [region]. For the common
/// non-overlapping case the sum equals the exact union coverage. When zones
/// OVERLAP each other the shared sub-region is counted once per zone, so the
/// raw sum can exceed the true covered fraction; it is a conservative UPPER
/// BOUND and is clamped to 1 before being returned. Over-estimating coverage
/// only ever makes [isAdmissibleRegion] and [admitDetection] STRICTER (they
/// discard more detections), so overlapping zones can never relax masking or
/// cause a masked detection to be admitted. The result therefore always stays
/// within [trueCoveredFraction, 1] for the overlap case and never dips below
/// the true coverage, so it never under-masks (LOW-23).
double maskedFraction(Rect region, List<Rect> zones) {
  if (region.area <= 0) return 0;
  var covered = 0.0;
  for (final z in zones) {
    final i = region.intersection(z);
    if (i != null) covered += i.area;
  }
  final f = covered / region.area;
  return f > 1 ? 1 : f;
}

/// True when [region] is admissible for processing: it is not substantially
/// inside a privacy zone (FR-11.1). A region whose masked fraction meets or
/// exceeds [threshold] is excluded so masked pixels are never processed.
bool isAdmissibleRegion(Rect region, List<Rect> zones,
    {double threshold = 0.5}) {
  return maskedFraction(region, zones) < threshold;
}

/// Guarantee masked pixels are never emitted (FR-11.1): given a candidate
/// detection [region] and the privacy [zones], return the region only if its
/// CENTER is outside every zone AND it is admissible; otherwise null (discarded).
/// This is the single gate every detection passes through before it can feed the
/// presence signal (FR-5.4).
Rect? admitDetection(Rect region, List<Rect> zones, {double threshold = 0.5}) {
  final c = region.center;
  if (zones.any((z) => z.contains(c))) return null; // center is masked
  if (!isAdmissibleRegion(region, zones, threshold: threshold)) return null;
  return region;
}

/// Mask the privacy [zones] out of [frame] BEFORE any detection runs (MED-08,
/// FR-11.1). The audit found detection ran on the full frame and masked
/// detections were only filtered afterward, so masked pixels were processed. The
/// correct order is mask first, then detect: this returns the sub-rectangles of
/// [frame] that remain after the masked zones are removed, so a detector only
/// ever sees unmasked pixels. The result is the frame clipped to exclude each
/// zone (when zones overlap, their union is removed).
///
/// Overlap handling (LOW-23): zones are removed by subtracting each one in turn
/// from the running region set. Each [_subtract] returns disjoint sub-rectangles
/// of its input that lie entirely OUTSIDE the subtracted zone, so the invariant
/// "every remaining region is disjoint from every already-removed zone and from
/// every other remaining region" holds after each step. Consequently the output
/// rectangles never overlap each other and never overlap any masked zone even
/// when the input zones overlap one another. The subtraction is only ever
/// additive in what it removes, so it can never leave a masked pixel in the
/// result (it never under-masks); overlapping input zones at worst remove the
/// same pixel twice, which is harmless.
///
/// This is pure geometry over normalized rectangles; the live vision binding
/// zeroes the corresponding pixel regions on device before inference.
List<Rect> maskBeforeDetection(Rect frame, List<Rect> zones) {
  // Start with the whole frame and subtract each zone's intersection by
  // splitting the remaining regions around it. For v1 there are at most a
  // handful of zones, so a straightforward rectangle-subtraction is enough.
  // Because each _subtract yields regions disjoint from the removed zone, this
  // stays correct even when later zones overlap earlier ones (LOW-23).
  var regions = <Rect>[frame];
  for (final zone in zones) {
    final next = <Rect>[];
    for (final r in regions) {
      next.addAll(_subtract(r, zone));
    }
    regions = next;
  }
  return regions;
}

/// Subtract [zone] from [r], returning the (up to four) rectangles of [r] that
/// lie outside [zone]. When they do not overlap, [r] is returned unchanged.
///
/// The returned strips are mutually disjoint and none of them intersects
/// [zone]: the top and bottom strips span the full width of [r] but lie outside
/// the overlap's vertical band, while the left and right strips are confined to
/// the overlap's vertical band and lie outside it horizontally. This disjoint,
/// zone-free output is what lets [maskBeforeDetection] subtract overlapping
/// zones one after another without ever producing overlapping output rectangles
/// or leaving a masked pixel behind (LOW-23).
List<Rect> _subtract(Rect r, Rect zone) {
  final overlap = r.intersection(zone);
  if (overlap == null) return <Rect>[r];
  final parts = <Rect>[];
  // Top strip (above the overlap).
  if (overlap.top > r.top) {
    parts
        .add(Rect(x: r.x, y: r.y, width: r.width, height: overlap.top - r.top));
  }
  // Bottom strip (below the overlap).
  if (overlap.bottom < r.bottom) {
    parts.add(Rect(
        x: r.x,
        y: overlap.bottom,
        width: r.width,
        height: r.bottom - overlap.bottom));
  }
  // Left strip (beside the overlap, within its vertical band).
  if (overlap.left > r.left) {
    parts.add(Rect(
        x: r.x,
        y: overlap.top,
        width: overlap.left - r.left,
        height: overlap.height));
  }
  // Right strip (beside the overlap, within its vertical band).
  if (overlap.right < r.right) {
    parts.add(Rect(
        x: overlap.right,
        y: overlap.top,
        width: r.right - overlap.right,
        height: overlap.height));
  }
  return parts;
}
