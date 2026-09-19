// Captions-Only screen (Task 17, FR-12.1..FR-12.4, N9; AT-6, AT-10). A
// receive-only conversation screen: live captions of the visitor, video, alerts,
// and history all work; only spoken replies are unavailable, so there is NO
// reply bar. A persistent, non-alarming banner states the situation, and a
// one-tap "Open Ring app" action lets a hearing household member respond
// (FR-12.3). There is no visitor-facing prompt (N9). Captions-Only is a
// first-class mode, not an error state (FR-12.4), so it renders the same live
// video + caption layout as the two-way screen, minus the reply bar.

import 'package:flutter/material.dart';

import '../captions/caption_surface.dart';
import '../settings/settings_state.dart';
import 'conversation_screen.dart';
import 'ring_app_launcher.dart';
import 'session_controller.dart';
import 'session_state.dart';
import 'watermark_safe_area.dart';

/// The exact persistent banner text required by FR-12.2. Dash-free (NFR-10).
const String kCaptionsOnlyBanner =
    'Replies unavailable on this device. You can still see what your visitor says.';

class CaptionsOnlyScreen extends StatelessWidget {
  const CaptionsOnlyScreen({
    super.key,
    required this.controller,
    required this.launcher,
    this.settings,
    this.videoSurfaceBuilder,
  });

  final SessionController controller;
  final RingAppLauncher launcher;

  /// The resident's accessibility settings driving caption scale + the enforced
  /// contrast foreground (FR-10.2, NFR-2). Defaults to accessible defaults.
  final ThresholdSettings? settings;
  final VideoSurfaceBuilder? videoSurfaceBuilder;

  ThresholdSettings get _settings => settings ?? ThresholdSettings.defaults();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _build(context, controller.snapshot),
    );
  }

  Widget _build(BuildContext context, SessionSnapshot snap) {
    final builder = videoSurfaceBuilder ?? (_) => const ColoredBox(color: Color(0xFF15151B));
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0F),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Semantics(
              label: 'Live video from your doorbell',
              image: true,
              child: builder(context),
            ),
            Padding(
              padding: watermarkSafeInsets(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Persistent, non-alarming banner (FR-12.2). Not an error color.
                  _CaptionsOnlyBanner(launcher: launcher),
                  const Spacer(),
                  // Caption region: the visitor's speech, receive-only (FR-12.1).
                  Semantics(
                    liveRegion: true,
                    label: 'Visitor captions',
                    child: Container(
                      key: const ValueKey('captions-only-region'),
                      constraints: const BoxConstraints(minHeight: 160),
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _settings.captionBackground.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      // Real caption turns with confidence emphasis + the
                      // enforced accessibility settings (FR-5.3/5.3a, FR-10.2,
                      // NFR-2; AT-4, AT-9).
                      child: CaptionSurface(
                        turns: controller.captionTurns,
                        settings: _settings,
                      ),
                    ),
                  ),
                  // NO reply bar in Captions-Only Mode (FR-12.1).
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Semantics(
                        button: true,
                        label: 'End session',
                        excludeSemantics: true,
                        child: FilledButton.tonal(
                          key: const ValueKey('captions-only-end'),
                          onPressed: () => controller.end(),
                          child: const Text('End'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptionsOnlyBanner extends StatelessWidget {
  const _CaptionsOnlyBanner({required this.launcher});
  final RingAppLauncher launcher;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('captions-only-banner'),
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // Non-alarming: informational blue-grey, not an error red (FR-12.2).
        color: const Color(0xFF2A3A4A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Semantics(
            liveRegion: true,
            label: kCaptionsOnlyBanner,
            excludeSemantics: true,
            child: const Text(
              kCaptionsOnlyBanner,
              style: TextStyle(color: Colors.white, fontSize: 16, height: 1.3),
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            button: true,
            label: 'Open Ring app',
            excludeSemantics: true,
            child: OutlinedButton.icon(
              key: const ValueKey('open-ring-app'),
              onPressed: () => launcher.openRingApp(),
              icon: const Icon(Icons.open_in_new, color: Colors.white),
              label: const Text(
                'Open Ring app',
                style: TextStyle(color: Colors.white),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white70),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
