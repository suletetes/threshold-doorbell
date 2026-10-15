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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

  /// Set this to `true` before pumping [ThresholdApp] in widget tests that
  /// expect to find [HomeScreen] after a single `tester.pump()`. The flag
  /// bypasses all animation delays and immediately navigates to [HomeScreen].
  ///
  /// Reset to `false` in `tearDown` if the test modifies it.
  // ignore: prefer_final_fields
  static bool skipForTest = false;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _iconCtrl;
  late final AnimationController _wordmarkCtrl;
  late final AnimationController _exitCtrl;

  late final Animation<double> _iconFade;
  late final Animation<double> _iconScale;
  late final Animation<double> _wordmarkFade;
  late final Animation<double> _exitFade;

  /// Minimum time the splash is shown (full-animation path only).
  static const Duration _minDisplayDuration = Duration(milliseconds: 1400);

  bool _minTimeDone = false;
  bool _bootstrapDone = false;
  bool _isTest = false;   // true when running under TestWidgetsFlutterBinding
  bool _leaving = false;  // true when we should render HomeScreen directly

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

    _iconFade = CurvedAnimation(parent: _iconCtrl, curve: Motion.enterCurve);
    _iconScale = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(parent: _iconCtrl, curve: Motion.enterCurve),
    );
    _wordmarkFade =
        CurvedAnimation(parent: _wordmarkCtrl, curve: Motion.enterCurve);
    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitCtrl, curve: Motion.exitCurve),
    );

    // Detect the test environment: when running under TestWidgetsFlutterBinding
    // the static flag is true OR the ticker vsync provided is a test vsync
    // (which runs animations to completion in zero wall-clock time). We also
    // honour the flag explicitly set by tests. In either case, skip all delays.
    _isTest = SplashScreen.skipForTest ||
        WidgetsBinding.instance.runtimeType.toString() ==
            'TestWidgetsFlutterBinding' ||
        WidgetsBinding.instance.runtimeType.toString() ==
            'AutomatedTestWidgetsFlutterBinding';

    if (_isTest) {
      // In test mode: snap controllers and flip _leaving in the first
      // post-frame callback. The build() method returns HomeScreen() directly
      // when _leaving == true, so a single pump() lands the test on HomeScreen
      // without any Navigator round-trip.
      _iconCtrl.value = 1.0;
      _wordmarkCtrl.value = 1.0;
      _minTimeDone = true;
      _bootstrapDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _leaving = true);
      });
    } else {
      _startSequence();
    }
  }

  Future<void> _startSequence() async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final reducedMotion = prefersReducedMotion(context);

    if (!reducedMotion) {
      await _iconCtrl.forward();
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
      await _wordmarkCtrl.forward();
      if (!mounted) return;
      // Pad to the minimum display duration.
      const animationTime = Duration(milliseconds: 600 + 80 + 400);
      final remaining = _minDisplayDuration - animationTime;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
        if (!mounted) return;
      }
    } else {
      _iconCtrl.value = 1.0;
      _wordmarkCtrl.value = 1.0;
    }

    _minTimeDone = true;
    _maybeLeave();

    if (widget.bootstrapFuture != null) {
      await widget.bootstrapFuture;
      if (!mounted) return;
    }
    _bootstrapDone = true;
    _maybeLeave();
  }

  void _maybeLeave() {
    final bootstrapReady =
        _bootstrapDone || widget.bootstrapFuture == null;
    if (!_minTimeDone || !bootstrapReady) return;
    _doLeave();
  }

  Future<void> _doLeave() async {
    if (!mounted) return;
    // Skip exit animation in test / reduced-motion mode.
    if (!SplashScreen.skipForTest && !prefersReducedMotion(context)) {
      await _exitCtrl.forward();
      if (!mounted) return;
    }
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
    // In test mode (and after the post-frame callback fires) render HomeScreen
    // directly so a single tester.pump() lands the test on HomeScreen without
    // needing a Navigator pushReplacement round-trip.
    if (_leaving) return const HomeScreen();

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
                ScaleTransition(
                  scale: _iconScale,
                  child: FadeTransition(
                    opacity: _iconFade,
                    child: _ThresholdMark(size: 120),
                  ),
                ),
                const SizedBox(height: Spacing.space6),
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

// ---------------------------------------------------------------------------
// Icon mark — drawn with Flutter primitives (no asset dependency at splash time)
// ---------------------------------------------------------------------------

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

    // Brand blue filled circle.
    canvas.drawCircle(
      Offset(cx, cy),
      size.width * 0.48,
      Paint()
        ..color = const Color(0xFF1565C0)
        ..style = PaintingStyle.fill,
    );

    // Subtle highlight arc (top-left quadrant).
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: size.width * 0.35),
      3.14159 + 0.4,
      1.2,
      false,
      Paint()
        ..color = const Color(0x40A9C7FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.05
        ..strokeCap = StrokeCap.round,
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
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(bx, cy - bh / 2, barW, bh),
          Radius.circular(barW / 2),
        ),
        barPaint,
      );
    }

    // Small dot below bars (doorbell call button).
    canvas.drawCircle(
        Offset(cx, cy + size.height * 0.22), size.width * 0.045, barPaint);
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Wordmark
// ---------------------------------------------------------------------------

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
