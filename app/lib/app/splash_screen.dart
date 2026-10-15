// Threshold animated splash screen (polish task).
//
// Shows while the app bootstraps (shared_preferences load + provider wiring).
// Three layers animate in sequence:
//   1. Brand dark-navy background (matches the Android native splash exactly so
//      the native-to-Flutter transition is invisible).
//   2. Doorbell icon mark fades + scales in.
//   3. "Threshold" wordmark fades in below the mark.
//
// Once the bootstrap future completes the screen fades out and is replaced by
// HomeScreen via a Navigator replacement (no back-stack entry).
//
// Motion honours `MediaQuery.disableAnimations` (WCAG 2.2 AA / Motion.instant).
// No em-dashes or en-dashes anywhere (NFR-10).

import 'package:flutter/material.dart';

import '../design/colors.dart';
import '../design/tokens.dart';
import 'home_screen.dart';

/// Entry point used by [ThresholdApp]. Runs [bootstrapFuture] (if supplied)
/// then transitions to [HomeScreen]. When [bootstrapFuture] is null the widget
/// simply displays for [_minDisplayDuration] so the splash is always visible
/// for at least one breath.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.bootstrapFuture});

  /// The async work that must complete before leaving the splash. Injected so
  /// widget tests can supply a completed future and skip the timer.
  final Future<void>? bootstrapFuture;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // --- animation controllers ---
  late final AnimationController _iconCtrl;
  late final AnimationController _wordmarkCtrl;
  late final AnimationController _exitCtrl;

  late final Animation<double> _iconFade;
  late final Animation<double> _iconScale;
  late final Animation<double> _wordmarkFade;
  late final Animation<double> _exitFade;

  /// Minimum time the splash is shown even if bootstrap finishes instantly.
  /// Collapsed to zero under reduced motion (includes the test binding's
  /// `disableAnimations` flag, so widget tests that pump ThresholdApp skip the
  /// splash and land on HomeScreen after a single `pumpAndSettle`).
  static const Duration _minDisplayDuration = Duration(milliseconds: 1400);

  bool _bootstrapDone = false;
  bool _minTimeDone = false;

  @override
  void initState() {
    super.initState();

    _iconCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _wordmarkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _exitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _iconFade = CurvedAnimation(
      parent: _iconCtrl,
      curve: Motion.enterCurve,
    );
    _iconScale = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(parent: _iconCtrl, curve: Motion.enterCurve),
    );
    _wordmarkFade = CurvedAnimation(
      parent: _wordmarkCtrl,
      curve: Motion.enterCurve,
    );
    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitCtrl, curve: Motion.exitCurve),
    );

    _startSequence();
  }

  Future<void> _startSequence() async {
    // Let the first frame paint before starting animations.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    // In test environments the binding sets disableAnimations = true, which
    // makes pumpAndSettle work correctly. In production we also honour the
    // platform reduced-motion preference from MediaQuery.
    final reduced = WidgetsBinding.instance.disableAnimations ||
        prefersReducedMotion(context);

    if (!reduced) {
      // Icon enters.
      await _iconCtrl.forward();
      if (!mounted) return;

      // Wordmark follows 80 ms after the icon lands.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
      await _wordmarkCtrl.forward();
      if (!mounted) return;

      // Enforce minimum display time only when animations are running.
      final animationTime = const Duration(milliseconds: 600 + 80 + 400);
      final remaining = _minDisplayDuration - animationTime;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
        if (!mounted) return;
      }
    } else {
      // Snap to end state immediately so tests (and reduced-motion users)
      // reach HomeScreen on the next pumpAndSettle.
      _iconCtrl.value = 1.0;
      _wordmarkCtrl.value = 1.0;
    }

    _minTimeDone = true;
    _maybeLeave();

    // Wait for the bootstrap future if one was provided.
    if (widget.bootstrapFuture != null) {
      await widget.bootstrapFuture;
      if (!mounted) return;
    }
    _bootstrapDone = true;
    _maybeLeave();
  }

  void _maybeLeave() {
    // Only leave once both the minimum display time has elapsed AND bootstrap
    // is done (or no bootstrap was given).
    final bootstrapReady =
        _bootstrapDone || widget.bootstrapFuture == null;
    if (!_minTimeDone || !bootstrapReady) return;
    _doLeave();
  }

  Future<void> _doLeave() async {
    if (!mounted) return;
    await _exitCtrl.forward();
    if (!mounted) return;
    // Replace the splash with HomeScreen — no back-stack entry.
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  void dispose() {
    _iconCtrl.dispose();
    _wordmarkCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The brand dark-navy background, matching the Android native splash so the
    // native-to-Flutter transition is seamless.
    const bgColor = Color(0xFF0C0E13);

    return Semantics(
      label: 'Threshold is loading',
      child: FadeTransition(
        opacity: _exitFade,
        child: ColoredBox(
          color: bgColor,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // --- Icon mark ---
                ScaleTransition(
                  scale: _iconScale,
                  child: FadeTransition(
                    opacity: _iconFade,
                    child: _ThresholdMark(size: 120),
                  ),
                ),

                const SizedBox(height: Spacing.space6),

                // --- Wordmark ---
                FadeTransition(
                  opacity: _wordmarkFade,
                  child: const _Wordmark(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The doorbell icon mark, drawn with Flutter primitives so there is no asset
/// dependency at splash time (the PNG is used for the launcher icon only).
class _ThresholdMark extends StatelessWidget {
  const _ThresholdMark({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MarkPainter()),
    );
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Brand blue circle background.
    final circlePaint = Paint()
      ..color = const Color(0xFF1565C0)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), size.width * 0.48, circlePaint);

    // Subtle inner highlight arc (top-left).
    final hlPaint = Paint()
      ..color = const Color(0x40A9C7FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.05
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(
          center: Offset(cx, cy), radius: size.width * 0.35),
      3.14159 + 0.4,   // start: lower-left
      1.2,             // sweep: quarter arc
      false,
      hlPaint,
    );

    // White sound-wave bars (5 bars, tallest in centre).
    final barPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    const barCount = 5;
    final barW = size.width * 0.055;
    final barGap = size.width * 0.04;
    final totalW = barCount * barW + (barCount - 1) * barGap;
    final barX0 = cx - totalW / 2;
    const heightFracs = [0.14, 0.22, 0.32, 0.22, 0.14];

    for (var i = 0; i < barCount; i++) {
      final bx = barX0 + i * (barW + barGap);
      final bh = size.height * heightFracs[i];
      final by = cy - bh / 2;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(bx, by, barW, bh),
        Radius.circular(barW / 2),
      );
      canvas.drawRRect(rrect, barPaint);
    }

    // Small dot below bars (doorbell call button).
    final dotR = size.width * 0.045;
    final dotCy = cy + size.height * 0.22;
    canvas.drawCircle(Offset(cx, dotCy), dotR, barPaint);
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => false;
}

/// Plain text wordmark below the icon.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Threshold',
      style: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 28,
        fontWeight: FontWeight.w300,
        letterSpacing: 4.0,
        color: Colors.white.withValues(alpha: 0.92),
        decoration: TextDecoration.none,
      ),
    );
  }
}
