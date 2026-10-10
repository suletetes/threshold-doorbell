// Loading placeholder (UI/UX audit section 4, "Perceived performance": "no
// skeletons, no optimistic states, no staged reveal. The first frame of any
// data-bearing surface is empty").
//
// Two deliberate decisions:
//
//   1. The pulse is FINITE. It runs a fixed number of cycles and then rests as a
//      static block. An endlessly shimmering placeholder is the convention, but
//      an animation that never ends is an animation that never stops asking for
//      attention, and on this product's surfaces the thing that deserves
//      attention is the caption text arriving. A bounded pulse says "still
//      working" and then gets out of the way. It also keeps the widget tree
//      settleable, which an infinite ticker does not.
//   2. It is hidden from screen readers unless the caller names it. A skeleton is
//      a drawing of content that does not exist yet; announcing four of them is
//      noise. The surrounding status panel already carries the live region that
//      says what is loading.
//
// The pulse duration goes through motionDuration(), so under reduced motion the
// block renders at its resting value immediately and never moves (audit design
// principle 3).

import 'package:flutter/material.dart';

import '../tokens.dart';

/// A rectangular placeholder standing in for content that has not arrived.
class SkeletonBlock extends StatefulWidget {
  const SkeletonBlock({
    super.key,
    required this.height,
    this.width,
    this.borderRadius = Radii.roundedSmall,
    this.semanticsLabel,
  });

  /// The placeholder height in dp. Callers pass a spacing token.
  final double height;

  /// The placeholder width in dp, or null to fill the available width.
  final double? width;

  final BorderRadius borderRadius;

  /// When set, the block is announced with this label. When null (the default)
  /// it is hidden from the semantics tree as decoration.
  final String? semanticsLabel;

  /// How many full pulses run before the block rests.
  static const int pulseCycles = 4;

  /// The resting opacity of the placeholder fill.
  static const double restOpacity = 0.08;

  /// The peak opacity at the top of a pulse.
  static const double peakOpacity = 0.20;

  /// The whole finite pulse: [pulseCycles] cycles of a [Motion.slow] rise and a
  /// [Motion.slow] fall. Not const because scaling a Duration is not a const
  /// expression; deriving it from the motion token beats restating 480 here.
  static final Duration totalPulse = Motion.slow * (pulseCycles * 2);

  @override
  State<SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<SkeletonBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: SkeletonBlock.totalPulse,
    );
    _opacity = TweenSequence<double>(<TweenSequenceItem<double>>[
      for (var i = 0;
          i < SkeletonBlock.pulseCycles;
          i++) ...<TweenSequenceItem<double>>[
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: SkeletonBlock.restOpacity,
            end: SkeletonBlock.peakOpacity,
          ).chain(CurveTween(curve: Motion.standardCurve)),
          weight: 1,
        ),
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: SkeletonBlock.peakOpacity,
            end: SkeletonBlock.restOpacity,
          ).chain(CurveTween(curve: Motion.standardCurve)),
          weight: 1,
        ),
      ],
    ]).animate(_controller);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion collapses the whole pulse to zero, so forward() lands on
    // the resting value in the same frame and nothing ever animates.
    _controller.duration = motionDuration(context, SkeletonBlock.totalPulse);
    if (!_started) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color base = Theme.of(context).colorScheme.onSurface;
    final Widget block = AnimatedBuilder(
      animation: _opacity,
      builder: (BuildContext context, Widget? child) => DecoratedBox(
        decoration: BoxDecoration(
          color: base.withValues(alpha: _opacity.value),
          borderRadius: widget.borderRadius,
        ),
        child: child,
      ),
      child: SizedBox(width: widget.width, height: widget.height),
    );

    final String? label = widget.semanticsLabel;
    if (label == null) {
      // Decoration: a drawing of content that does not exist yet.
      return ExcludeSemantics(child: block);
    }
    return Semantics(
      label: label,
      container: true,
      child: ExcludeSemantics(child: block),
    );
  }
}
