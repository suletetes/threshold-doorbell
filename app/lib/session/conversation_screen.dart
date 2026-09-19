// Conversation (live session) screen (Task 12, FR-4.1..FR-4.8, FR-4.5; AT-3,
// AT-11, AT-12, AT-25). Hosts the WebView video surface (ARCH-1) with Flutter
// caption/control overlays drawn on top in a Stack, kept clear of the watermark
// corners (FR-4.5). The WebView binding is device-bound and behind SessionPort;
// this screen renders purely from the SessionController snapshot so every state
// is driven and asserted by widget tests without a device.
//
// The screen is fully usable with sound off and a screen reader on (G4): every
// interactive control and status region carries a Semantics label, and state
// changes are announced via live regions.

import 'package:flutter/material.dart';

import '../captions/caption_surface.dart';
import '../settings/settings_state.dart';
import 'session_controller.dart';
import 'session_state.dart';
import 'watermark_safe_area.dart';

/// A slot for the platform WebView surface. On device the composition root
/// replaces this with a WebViewWidget hosting app/spike/webrtc_audio_spike.html
/// style runtime (ARCH-1). Under `flutter test` it renders a labelled placeholder
/// so the overlay geometry and states are testable headless.
typedef VideoSurfaceBuilder = Widget Function(BuildContext context);

class ConversationScreen extends StatelessWidget {
  const ConversationScreen({
    super.key,
    required this.controller,
    this.settings,
    this.replyBar,
    this.videoSurfaceBuilder,
  });

  final SessionController controller;

  /// The resident's accessibility settings driving caption scale + the enforced
  /// contrast foreground (FR-10.2, NFR-2). Defaults to accessible defaults.
  final ThresholdSettings? settings;

  /// Optional reply bar built by the composition root (Task 15). When null (as
  /// in headless caption tests) no reply bar is shown.
  final Widget? replyBar;

  /// Optional device video surface. Defaults to the labelled placeholder.
  final VideoSurfaceBuilder? videoSurfaceBuilder;

  ThresholdSettings get _settings => settings ?? ThresholdSettings.defaults();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _buildForSnapshot(context, controller.snapshot),
    );
  }

  Widget _buildForSnapshot(BuildContext context, SessionSnapshot snap) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0F),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _videoLayer(context),
            // Overlays kept clear of the watermark corners (FR-4.5).
            Padding(
              padding: watermarkSafeInsets(),
              child: _overlayForState(context, snap),
            ),
            // A top status strip below the watermark band shows the live mode.
            Positioned(
              top: kWatermarkBandHeight,
              left: kWatermarkCornerInset,
              right: kWatermarkCornerInset,
              child: _ModeBadge(mode: snap.mode, state: snap.state),
            ),
            if (snap.state == SessionState.authRecovering)
              _AuthRecoveryPrompt(controller: controller),
          ],
        ),
      ),
    );
  }

  Widget _videoLayer(BuildContext context) {
    final builder = videoSurfaceBuilder ?? _placeholderSurface;
    return Semantics(
      label: 'Live video from your doorbell',
      image: true,
      child: builder(context),
    );
  }

  static Widget _placeholderSurface(BuildContext context) {
    // Headless placeholder for the WebView video surface (device-bound, ARCH-1).
    return const ColoredBox(color: Color(0xFF15151B));
  }

  Widget _overlayForState(BuildContext context, SessionSnapshot snap) {
    switch (snap.state) {
      case SessionState.connecting:
        return const _StatusPanel(
          key: ValueKey('status-connecting'),
          message: 'Connecting to your doorbell',
          showSpinner: true,
        );
      case SessionState.probing:
        return const _StatusPanel(
          key: ValueKey('status-probing'),
          message: 'Checking two way audio',
          showSpinner: true,
        );
      case SessionState.reconnecting:
        return const _StatusPanel(
          key: ValueKey('status-reconnecting'),
          message: 'Reconnecting to your doorbell',
          showSpinner: true,
        );
      case SessionState.backgrounded:
        return const _StatusPanel(
          key: ValueKey('status-backgrounded'),
          message: 'Session paused. It stays ready for up to five minutes.',
          showSpinner: false,
        );
      case SessionState.closing:
        return const _StatusPanel(
          key: ValueKey('status-closing'),
          message: 'Ending session',
          showSpinner: true,
        );
      case SessionState.error:
        return _ErrorPanel(
          key: const ValueKey('status-error'),
          message: snap.errorMessage ?? "Couldn't connect to your doorbell.",
        );
      case SessionState.authRecovering:
        // The modal prompt covers this; keep the last live layout beneath.
        return _LiveOverlay(
          controller: controller,
          snap: snap,
          settings: _settings,
          replyBar: replyBar,
        );
      case SessionState.live:
        return _LiveOverlay(
          controller: controller,
          snap: snap,
          settings: _settings,
          replyBar: replyBar,
        );
      case SessionState.idle:
        return const SizedBox.shrink();
    }
  }
}

/// The live overlay: caption region (bottom, dominant) plus the end-session
/// control. Reply bar is added by Task 15 and hidden when Captions-Only.
class _LiveOverlay extends StatelessWidget {
  const _LiveOverlay({
    required this.controller,
    required this.snap,
    required this.settings,
    this.replyBar,
  });

  final SessionController controller;
  final SessionSnapshot snap;
  final ThresholdSettings settings;
  final Widget? replyBar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Semantics(
              button: true,
              label: 'End session',
              excludeSemantics: true,
              child: FilledButton.tonal(
                key: const ValueKey('end-session'),
                onPressed: () => controller.end(),
                child: const Text('End'),
              ),
            ),
          ),
        ),
        const Spacer(),
        // Caption region dominates the lower part of the screen (design §8.2).
        // Renders REAL caption turns with confidence emphasis + the enforced
        // accessibility settings (FR-5.3/5.3a, FR-10.2, NFR-2; AT-4, AT-9).
        Semantics(
          liveRegion: true,
          label: 'Visitor captions',
          child: Container(
            key: const ValueKey('caption-region'),
            constraints: const BoxConstraints(minHeight: 160),
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: settings.captionBackground.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: CaptionSurface(
              turns: controller.captionTurns,
              settings: settings,
            ),
          ),
        ),
        // The reply bar (Task 15) when the composition root supplies one and
        // outbound is available (the bar hides itself when unavailable).
        if (replyBar != null) replyBar!,
      ],
    );
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.mode, required this.state});
  final SessionCaptionMode mode;
  final SessionState state;

  @override
  Widget build(BuildContext context) {
    if (state == SessionState.idle) return const SizedBox.shrink();
    final label = mode == SessionCaptionMode.privacy
        ? 'Privacy Mode'
        : 'Clarity Mode';
    return Align(
      alignment: Alignment.topCenter,
      child: Semantics(
        label: 'Active caption mode: $label',
        child: Container(
          key: const ValueKey('mode-badge'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xCC1565C0),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({super.key, required this.message, required this.showSpinner});
  final String message;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        label: message,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (showSpinner)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: CircularProgressIndicator(),
              ),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        label: message,
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 20),
        ),
      ),
    );
  }
}

/// The single, non-destructive re-authentication prompt (FR-1.5, AT-12). There
/// is exactly one recovery path; the controller enforces one prompt at a time.
class _AuthRecoveryPrompt extends StatelessWidget {
  const _AuthRecoveryPrompt({required this.controller});
  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xB3000000),
        child: Center(
          child: Semantics(
            container: true,
            label: 'Sign in again to continue. Your conversation is saved.',
            child: Card(
              key: const ValueKey('auth-recovery-prompt'),
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      'Sign in again to continue',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your conversation is saved and will resume once you sign in.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: <Widget>[
                        TextButton(
                          key: const ValueKey('auth-recovery-cancel'),
                          onPressed: () =>
                              controller.completeAuthRecovery(success: false),
                          child: const Text('Not now'),
                        ),
                        FilledButton(
                          key: const ValueKey('auth-recovery-signin'),
                          onPressed: () =>
                              controller.completeAuthRecovery(success: true),
                          child: const Text('Sign in'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
