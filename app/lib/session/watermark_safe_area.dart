// Watermark-safe overlay geometry (Task 12, FR-4.5). Ring requires a mandatory
// watermark in the top-left and top-right corners of the inbound video. UI
// overlays (captions, controls) must stay clear of those corners. This is pure
// geometry so the clearance rule is unit-testable without a render surface.

import 'package:flutter/widgets.dart';

/// The height reserved at the top of the video for the Ring watermark corners
/// (FR-4.5). Overlays anchored below this band never collide with either corner.
const double kWatermarkBandHeight = 56.0;

/// The horizontal inset from each edge that the watermark occupies (FR-4.5).
const double kWatermarkCornerInset = 96.0;

/// Compute EdgeInsets that keep an overlay clear of the top watermark corners
/// (FR-4.5). The top inset always clears the band. When [fullWidth] is false the
/// overlay is also inset horizontally so a top-anchored control never overlaps a
/// corner even within the band.
EdgeInsets watermarkSafeInsets({bool fullWidth = true}) {
  return EdgeInsets.only(
    top: kWatermarkBandHeight,
    left: fullWidth ? 0 : kWatermarkCornerInset,
    right: fullWidth ? 0 : kWatermarkCornerInset,
  );
}

/// True when a [rect] within a video surface of [size] avoids both watermark
/// corners (FR-4.5). Used by the widget test to assert overlays stay clear.
bool clearsWatermarkCorners(Rect rect, Size size) {
  const topLeftCorner = Rect.fromLTWH(0, 0, kWatermarkCornerInset, kWatermarkBandHeight);
  final topRightCorner = Rect.fromLTWH(
    size.width - kWatermarkCornerInset,
    0,
    kWatermarkCornerInset,
    kWatermarkBandHeight,
  );
  return !rect.overlaps(topLeftCorner) && !rect.overlaps(topRightCorner);
}
