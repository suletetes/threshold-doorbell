// Incoming-doorbell ringing screen (FR-3.3, FR-4.x). The resident is deaf, so a
// ring is presented like an incoming call they can SEE and FEEL: a full screen
// takeover with a pulsing visual, an optional photosensitivity-safe screen
// flash, and three large actions. The phone also vibrates and shows a
// call-style notification (DoorbellAlertService), driven by the host.
//
// Actions (FR: resident must be able to accept, promise, or decline):
//   Answer      -> start the live captioned session.
//   I'm coming  -> speak "Please wait, I am coming to the door" at the door, then answer.
//   Decline     -> speak "Sorry, I cannot come to the door right now" and dismiss.
// If nobody acts within 30 seconds the ring is marked missed and dismissed.
//
// No audio cue anywhere: every state is visual plus haptic. All copy is
// dash-free (NFR-10). Motion is gated on reduced-motion (tokens.motionDuration).

import 'dart:async';

import 'package:flutter/material.dart';

import '../alerts/strobe_config.dart';
import '../design/components/components.dart';
import '../design/tokens.dart';

/// Spoken lines for the two non-answer actions. Dash-free (NFR-10).
const String kComingSpokenLine = 'Please wait, I am coming to the door.';
const String kDeclineSpokenLine = 'Sorry, I cannot come to the door right now.';

/// How long the ring shows before it is treated as missed (FR: 30s no-answer).
const Duration kRingTimeout = Duration(seconds: 30);

class RingingScreen extends StatefulWidget {
  const RingingScreen({
    super.key,
    required this.onAnswer,
    required this.onComing,
    required this.onDecline,
    required this.onMissed,
    this.strobeEnabled = false,
  });

  /// The resident accepted: open the captioned session.
  final VoidCallback onAnswer;

  /// The resident is on the way: speak the coming line, then open the session.
  final VoidCallback onComing;

  /// The resident declined: speak the decline line and dismiss.
  final VoidCallback onDecline;

  /// Nobody acted within [kRingTimeout]: mark missed and dismiss.
  final VoidCallback onMissed;

  /// Whether the photosensitivity-safe screen flash is enabled (FR-9.4).
  final bool strobeEnabled;

  @override
  State<RingingScreen> createState() => _RingingScreenState();
}

class _RingingScreenState extends State<RingingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _missedTimer;
  Timer? _strobeTimer;
  Timer? _strobeStop;
  bool _strobeOn = false;
  bool _acted = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    // Missed timeout: fires once unless the resident acts first.
    _missedTimer = Timer(kRingTimeout, () {
      if (!_acted && mounted) {
        _acted = true;
        widget.onMissed();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeStartStrobe();
  }

  void _maybeStartStrobe() {
    if (!widget.strobeEnabled || _strobeTimer != null) return;
    if (prefersReducedMotion(context)) return; // never flash under reduced motion
    final cfg = StrobeConfig.safe(
      enabled: true,
      requestedFlashesPerSecond: kRecommendedFlashesPerSecond,
    );
    _strobeTimer = Timer.periodic(
      Duration(milliseconds: cfg.flashPeriodMs),
      (_) {
        if (mounted) setState(() => _strobeOn = !_strobeOn);
      },
    );
    // Hard stop after the safety cap so it never flashes indefinitely (MED-09).
    _strobeStop = Timer(cfg.maxDuration, () {
      _strobeTimer?.cancel();
      _strobeTimer = null;
      if (mounted) setState(() => _strobeOn = false);
    });
  }

  void _act(VoidCallback action) {
    if (_acted) return;
    _acted = true;
    action();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _missedTimer?.cancel();
    _strobeTimer?.cancel();
    _strobeStop?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      // The ring is a decision point: the system back gesture declines it rather
      // than silently dropping the visitor.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _act(widget.onDecline);
      },
      child: Scaffold(
        backgroundColor:
            _strobeOn ? scheme.primaryContainer : scheme.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.space6),
            child: Column(
              children: <Widget>[
                const Spacer(),
                // Pulsing doorbell glyph: the visual "ringing" cue.
                ScaleTransition(
                  scale: Tween<double>(begin: 0.92, end: 1.08).animate(
                    CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                  ),
                  child: Container(
                    width: Spacing.space10 * 2,
                    height: Spacing.space10 * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary,
                    ),
                    child: Icon(
                      Icons.doorbell_rounded,
                      size: Spacing.space10,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.space7),
                Text(
                  'Someone is at your door',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: Spacing.space3),
                Text(
                  'Answer to see captions of what they say, '
                  'and reply out loud.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const Spacer(),
                // Answer: the primary, largest action.
                PrimaryActionCard(
                  key: const ValueKey('ring-answer'),
                  icon: Icons.videocam_rounded,
                  label: 'Answer',
                  supportingText: 'See your visitor and reply.',
                  semanticsLabel: 'Answer the door',
                  onPressed: () => _act(widget.onAnswer),
                ),
                const SizedBox(height: Spacing.space3),
                // I'm coming: speaks a line at the door, then answers.
                Semantics(
                  button: true,
                  label: 'I am coming to the door',
                  excludeSemantics: true,
                  child: FilledButton.tonalIcon(
                    key: const ValueKey('ring-coming'),
                    style: FilledButton.styleFrom(
                      minimumSize:
                          const Size.fromHeight(TouchTarget.minimum + 8),
                      shape: const RoundedRectangleBorder(
                          borderRadius: Radii.roundedFull),
                    ),
                    onPressed: () => _act(widget.onComing),
                    icon: const Icon(Icons.directions_walk_rounded),
                    label: const Text('I am coming'),
                  ),
                ),
                const SizedBox(height: Spacing.space3),
                // Decline: destructive, speaks a polite line.
                Semantics(
                  button: true,
                  label: 'Decline the door',
                  excludeSemantics: true,
                  child: FilledButton.icon(
                    key: const ValueKey('ring-decline'),
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.error,
                      foregroundColor: scheme.onError,
                      minimumSize:
                          const Size.fromHeight(TouchTarget.minimum + 8),
                      shape: const RoundedRectangleBorder(
                          borderRadius: Radii.roundedFull),
                    ),
                    onPressed: () => _act(widget.onDecline),
                    icon: const Icon(Icons.call_end_rounded),
                    label: const Text('Decline'),
                  ),
                ),
                const SizedBox(height: Spacing.space4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
