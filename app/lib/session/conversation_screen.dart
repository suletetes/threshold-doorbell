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
//
// --- Presentation (UI/UX audit C1, C2, C4, C6, and section 4) ---------------
//
// This screen was the worst offender in the audit. What changed:
//
//   * C1/C2. It was a hardcoded dark island: a 0xFF0B0B0F scaffold and a
//     0xFF15151B video placeholder sitting between a light home screen and a
//     light settings screen. It is still dark, but now deliberately: this is a
//     media surface compositing overlays over inbound doorbell video, which is
//     dark whatever the platform theme is, so it pins the dark scheme for its
//     whole subtree. That turns an accident into a decision, and every component
//     drawn inside it resolves its colors against the scheme it is actually on.
//     The literals 0xFF0B0B0F, 0xFF15151B, 0xCC1565C0 and 0xB3000000 are gone.
//   * C4. The error state was a dead end: a centered Text with no icon, no
//     retry, and no way out, at the single highest stress moment in the product.
//     It now has an icon, the failure, a plain language cause, a primary Try
//     again wired to the controller's open path, and a secondary escape.
//   * C6. The screen swapped hard between connecting, probing, live,
//     reconnecting and error, and because every panel was centered text a state
//     change could be nearly invisible. That is dangerous here: the user gets no
//     audio cue, so motion is a redundant channel for state change, not
//     decoration. The panels now cross fade and rise through an AnimatedSwitcher
//     on the motion tokens, and every duration goes through motionDuration() so
//     a reduced-motion user gets the end state instantly.
//   * Section 4, responsive. There were no breakpoints and no orientation
//     handling, so in landscape the caption area was badly squeezed, which is
//     exactly the orientation someone props a phone in to read captions. There
//     is now a landscape layout that gives captions a full height column.
//   * Section 4, perceived performance. The connecting states preview the
//     caption region with skeleton lines instead of showing an empty screen.
//
// watermarkSafeInsets() and kWatermarkBandHeight are untouched (FR-4.5).

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../captions/caption_announcer.dart';
import '../captions/caption_surface.dart';
import '../design/colors.dart';
import '../design/components/components.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../settings/settings_state.dart';
import 'auth_port.dart';
import 'session_controller.dart';
import 'session_state.dart';
import 'watermark_safe_area.dart';

/// A slot for the platform WebView surface. On device the composition root
/// replaces this with a WebViewWidget hosting app/spike/webrtc_audio_spike.html
/// style runtime (ARCH-1). Under `flutter test` it renders a labelled placeholder
/// so the overlay geometry and states are testable headless.
typedef VideoSurfaceBuilder = Widget Function(BuildContext context);

/// The minimum height of the caption region in portrait (design section 8.2: the
/// caption region dominates the lower part of the screen).
const double kCaptionRegionMinHeight = 160.0;

/// The opacity of the blocking scrim behind the re-authentication prompt. Heavier
/// than a stock dialog scrim on purpose: it has to flatten arbitrary inbound
/// video so the prompt copy stays readable over it. Replaces the raw 0xB3000000
/// the audit flagged (C2).
const double kModalScrimOpacity = 0.72;

/// How far a state panel rises as it enters, in dp. Small enough to read as a
/// settling motion rather than a slide (audit C6).
const double kStatePanelRise = Spacing.space3;

/// The plain-language cause shown under a connection failure (audit C4: the error
/// state offered no cause and no path forward). Dash-free (NFR-10).
const String kConnectionFailureCause =
    'Your phone could not reach your doorbell. It may be offline, or your '
    'network may have dropped.';

/// The default headless video surface. Shared with the Captions-Only screen so
/// both media surfaces render the same placeholder.
Widget defaultVideoSurface(BuildContext context) {
  // Headless placeholder for the WebView video surface (device-bound, ARCH-1).
  return ColoredBox(color: Theme.of(context).colorScheme.surfaceContainer);
}

/// The theme every media surface in this app renders against. The conversation
/// and Captions-Only screens composite overlays over inbound doorbell video, so
/// they pin the dark scheme rather than following the platform (audit C1).
ThemeData mediaSurfaceTheme() => ThresholdTheme.dark();

class ConversationScreen extends StatelessWidget {
  const ConversationScreen({
    super.key,
    required this.controller,
    this.settings,
    this.replyBar,
    this.videoSurfaceBuilder,
    this.authPort,
  });

  final SessionController controller;

  /// The re-authentication binding used by the auth-recovery prompt (HIGH-09).
  /// When null (headless caption tests), the prompt resolves recovery directly
  /// so those tests do not need to supply an auth port.
  final AuthPort? authPort;

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
    return Theme(
      data: mediaSurfaceTheme(),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) =>
            _buildForSnapshot(context, controller.snapshot),
      ),
    );
  }

  Widget _buildForSnapshot(BuildContext context, SessionSnapshot snap) {
    final semantic = ThresholdSemanticColors.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The audit noted status-bar icon contrast against the near-black
      // conversation screen was left to chance. It is not any more.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: semantic.captionSurface,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              _videoLayer(context),
              // Overlays kept clear of the watermark corners (FR-4.5).
              Padding(
                padding: watermarkSafeInsets(),
                child: _animatedOverlay(context, snap),
              ),
              // A top status strip below the watermark band shows the live mode.
              Positioned(
                top: kWatermarkBandHeight,
                left: kWatermarkCornerInset,
                right: kWatermarkCornerInset,
                child: _ModeBadge(mode: snap.mode, state: snap.state),
              ),
              if (snap.state == SessionState.authRecovering)
                _AuthRecoveryPrompt(controller: controller, authPort: authPort),
            ],
          ),
        ),
      ),
    );
  }

  Widget _videoLayer(BuildContext context) {
    final builder = videoSurfaceBuilder ?? defaultVideoSurface;
    return Semantics(
      label: 'Live video from your doorbell',
      image: true,
      child: builder(context),
    );
  }

  /// Cross fades and rises between session states (audit C6). Every panel below
  /// carries a distinct key, which is what drives the transition; the live
  /// overlay keeps a stable key so an ordinary caption update does not restart
  /// an animation or rebuild the reply bar's state.
  Widget _animatedOverlay(BuildContext context, SessionSnapshot snap) {
    return AnimatedSwitcher(
      duration: motionDuration(context, Motion.emphasized),
      switchInCurve: Motion.enterCurve,
      switchOutCurve: Motion.exitCurve,
      // StackFit.expand, unlike the default loose layout builder, keeps the
      // panels filling the overlay area exactly as they did before the switcher
      // was introduced.
      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) =>
          Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      transitionBuilder: (Widget child, Animation<double> animation) =>
          FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, kStatePanelRise / kCaptionRegionMinHeight),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: _overlayForState(context, snap),
    );
  }

  Widget _overlayForState(BuildContext context, SessionSnapshot snap) {
    switch (snap.state) {
      case SessionState.connecting:
        return const _StatusPanel(
          key: ValueKey('status-connecting'),
          message: 'Connecting to your doorbell',
          supportingText: 'This usually takes a few seconds.',
          showSpinner: true,
          showCaptionPreview: true,
        );
      case SessionState.probing:
        return const _StatusPanel(
          key: ValueKey('status-probing'),
          message: 'Checking two way audio',
          supportingText: 'Finding out whether you can reply out loud.',
          showSpinner: true,
          showCaptionPreview: true,
        );
      case SessionState.reconnecting:
        return const _StatusPanel(
          key: ValueKey('status-reconnecting'),
          message: 'Reconnecting to your doorbell',
          supportingText:
              'Your captions continue as soon as the connection is back.',
          showSpinner: true,
          showCaptionPreview: true,
        );
      case SessionState.backgrounded:
        return const _StatusPanel(
          key: ValueKey('status-backgrounded'),
          message: 'Session paused. It stays ready for up to five minutes.',
          supportingText:
              'Come back to this screen to pick up where you left off.',
          icon: Icons.pause_circle_outline,
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
          controller: controller,
          message: snap.errorMessage ?? "Couldn't connect to your doorbell.",
        );
      case SessionState.authRecovering:
        // The modal prompt covers this; keep the last live layout beneath.
        return _LiveOverlay(
          key: const ValueKey('overlay-live'),
          controller: controller,
          snap: snap,
          settings: _settings,
          replyBar: replyBar,
        );
      case SessionState.live:
        return _LiveOverlay(
          key: const ValueKey('overlay-live'),
          controller: controller,
          snap: snap,
          settings: _settings,
          replyBar: replyBar,
        );
      case SessionState.idle:
        return const SizedBox.shrink(key: ValueKey('overlay-idle'));
    }
  }
}

/// The live overlay: caption region (dominant) plus the end-session control and
/// the reply bar. Reply bar is hidden when Captions-Only.
///
/// Two layouts (audit section 4, "Responsive and adaptive"). Portrait keeps the
/// original vertical stack: control at the top, captions anchored low where a
/// thumb is not covering them. Landscape hands captions a full height column on
/// one side and leaves the other side showing video, because a phone in landscape
/// is a phone someone propped up specifically to read.
class _LiveOverlay extends StatelessWidget {
  const _LiveOverlay({
    super.key,
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
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return isLandscape ? _landscape(context) : _portrait(context);
  }

  Widget _portrait(BuildContext context) {
    final Widget? bar = replyBar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _endControl(context),
        // Caption region dominates the lower part of the screen (design 8.2).
        // Bounded rather than free growing: a long conversation used to push this
        // Column past the screen and overflow, on the product's centerpiece
        // surface. It now fills what is available and scrolls beyond that, while
        // still shrink wrapping and sitting low when there is little to show.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.space3),
                  child: _CaptionPanel(
                    regionKey: const ValueKey('caption-region'),
                    controller: controller,
                    settings: settings,
                  ),
                ),
              ),
            ],
          ),
        ),
        // The reply bar (Task 15) when the composition root supplies one and
        // outbound is available (the bar hides itself when unavailable).
        if (bar != null) bar,
      ],
    );
  }

  Widget _landscape(BuildContext context) {
    final Widget? bar = replyBar;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Left: nothing drawn, so the video stays visible.
        const Spacer(),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _endControl(context),
              // A tall caption column instead of a squeezed strip.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: Spacing.space3,
                    right: Spacing.space3,
                    bottom: Spacing.space3,
                  ),
                  child: _CaptionPanel(
                    regionKey: const ValueKey('caption-region'),
                    controller: controller,
                    settings: settings,
                    fillHeight: true,
                  ),
                ),
              ),
              if (bar != null) bar,
            ],
          ),
        ),
      ],
    );
  }

  Widget _endControl(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.space3),
        child: Semantics(
          button: true,
          label: 'End session',
          onTap: () => controller.end(),
          excludeSemantics: true,
          child: FilledButton.tonalIcon(
            key: const ValueKey('end-session'),
            onPressed: () => controller.end(),
            icon: const Icon(Icons.call_end_rounded, size: Spacing.space5),
            label: const Text('End'),
          ),
        ),
      ),
    );
  }
}

/// The caption container (audit C7: it was a plain Container with a raw radius of
/// 12 and a 0.8 alpha on the caption background).
///
/// The fill is the resident's caption background composited over the
/// `captionSurface` role, which means two things. It is now OPAQUE, so inbound
/// video no longer bleeds through the surface the 4.5:1 floor was computed
/// against, which strengthens FR-10.2 rather than decorating it. And a
/// translucent caption background still lands on a designed dark surface instead
/// of on arbitrary video.
class _CaptionPanel extends StatefulWidget {
  const _CaptionPanel({
    required this.controller,
    required this.settings,
    required this.regionKey,
    this.fillHeight = false,
  });

  final SessionController controller;
  final ThresholdSettings settings;
  final Key regionKey;

  /// True when the panel should fill the height it is given (the landscape
  /// column). False lets it shrink wrap down to [kCaptionRegionMinHeight].
  final bool fillHeight;

  @override
  State<_CaptionPanel> createState() => _CaptionPanelState();
}

class _CaptionPanelState extends State<_CaptionPanel> {
  final CaptionAnnouncer _announcer = CaptionAnnouncer();

  @override
  Widget build(BuildContext context) {
    final semantic = ThresholdSemanticColors.of(context);
    final scheme = Theme.of(context).colorScheme;

    // Announce each newly finalized turn once, throttled (LOW-09), instead of
    // marking the whole container as a live region which re-reads the entire
    // run on every partial update. Scheduled post frame so the announcement
    // does not happen during build.
    final announcement =
        _announcer.announcementFor(widget.controller.captionTurns);
    if (announcement != null) {
      final view = View.of(context);
      final direction = Directionality.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        SemanticsService.sendAnnouncement(view, announcement, direction);
      });
    }

    // The caption run always scrolls, anchored to the bottom, because the newest
    // turn is the one being read. Under loose constraints the scroll view shrink
    // wraps to its content, so a short conversation still sizes to its text.
    final Widget captions = SingleChildScrollView(
      reverse: true,
      child: CaptionSurface(
        turns: widget.controller.captionTurns,
        settings: widget.settings,
      ),
    );
    return Semantics(
      label: 'Visitor captions',
      child: Container(
        key: widget.regionKey,
        constraints: widget.fillHeight
            ? null
            : const BoxConstraints(minHeight: kCaptionRegionMinHeight),
        padding: const EdgeInsets.all(Spacing.space4),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
              widget.settings.captionBackground, semantic.captionSurface),
          borderRadius: Radii.roundedLarge,
          border: Border.all(
            color: semantic.captionOnSurface.withValues(alpha: 0.12),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.45),
              blurRadius: Elevations.level4,
              offset: const Offset(0, Elevations.level1),
            ),
          ],
        ),
        child: captions,
      ),
    );
  }
}

/// The live caption mode, as the shared [Pill] in the `live` semantic role
/// (audit C2 and section 4: this was a bespoke pill built from a raw 0xCC1565C0
/// and a raw radius of 16, and it was text only).
class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.mode, required this.state});
  final SessionCaptionMode mode;
  final SessionState state;

  @override
  Widget build(BuildContext context) {
    if (state == SessionState.idle) return const SizedBox.shrink();
    final isPrivacy = mode == SessionCaptionMode.privacy;
    final label = isPrivacy ? 'Privacy Mode' : 'Clarity Mode';
    return Align(
      alignment: Alignment.topCenter,
      child: Pill(
        key: const ValueKey('mode-badge'),
        label: label,
        semanticsLabel: 'Active caption mode: $label',
        color: ThresholdSemanticColors.of(context).live,
        icon: isPrivacy ? Icons.lock_outline : Icons.cloud_outlined,
      ),
    );
  }
}

/// A transient session state: connecting, probing, reconnecting, paused, closing.
/// Themed, iconographic, and with a supporting line, because on this screen a
/// state change has to be visible to someone who gets no audio cue (audit C6).
class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    super.key,
    required this.message,
    required this.showSpinner,
    this.supportingText,
    this.icon,
    this.showCaptionPreview = false,
  });

  final String message;
  final bool showSpinner;

  /// What is happening, or what happens next. Dash-free (NFR-10).
  final String? supportingText;

  /// Shown instead of the spinner when the state is not "working".
  final IconData? icon;

  /// Previews the caption region with skeleton lines while connecting (audit
  /// section 4, "Perceived performance": the first frame of a data-bearing
  /// surface was empty).
  final bool showCaptionPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final String? supporting = supportingText;
    final IconData? leadingIcon = icon;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.space5),
        child: Semantics(
          container: true,
          liveRegion: true,
          label: supporting == null ? message : '$message $supporting',
          excludeSemantics: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (showSpinner)
                const _WorkingIndicator()
              else if (leadingIcon != null)
                Icon(leadingIcon,
                    size: Spacing.space8, color: scheme.onSurfaceVariant),
              const SizedBox(height: Spacing.space5),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: scheme.onSurface),
              ),
              if (supporting != null) ...<Widget>[
                const SizedBox(height: Spacing.space2),
                Text(
                  supporting,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              if (showCaptionPreview) ...<Widget>[
                const SizedBox(height: Spacing.space7),
                const _CaptionPreview(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The "working on it" marker for a transient state.
///
/// A spinning CircularProgressIndicator is the one animation in the app that
/// Flutter does not stop for a reduced-motion user, and it is also the one this
/// screen can most afford to lose: the panel's live region already states what is
/// happening in words. So under reduced motion this becomes a static marker and
/// nothing on the screen moves at all (audit design principle 3).
class _WorkingIndicator extends StatelessWidget {
  const _WorkingIndicator();

  /// The static stand in shown when the platform asks for reduced motion.
  static const IconData staticIcon = Icons.more_horiz_rounded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (prefersReducedMotion(context)) {
      return Icon(staticIcon, size: Spacing.space8, color: scheme.primary);
    }
    return const SizedBox(
      width: Spacing.space7,
      height: Spacing.space7,
      child: CircularProgressIndicator(strokeWidth: 3),
    );
  }
}

/// Skeleton lines standing where captions are about to appear.
class _CaptionPreview extends StatelessWidget {
  const _CaptionPreview();

  /// The relative widths of the previewed caption lines. Uneven on purpose: a
  /// stack of identical bars reads as a progress meter, not as text.
  static const List<double> lineWidthFactors = <double>[0.9, 0.7, 0.45];

  /// The widest the preview grows. It shrinks below this on a narrow screen
  /// rather than overflowing.
  static const double maxWidth = Spacing.space10 * 4;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final factor in lineWidthFactors)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.space2),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: factor,
                child: const SkeletonBlock(height: Spacing.space4),
              ),
            ),
        ],
      ),
    );
  }
}

/// The failure state, with a way forward (audit C4: "the single worst UX defect
/// found"). An icon, the failure, a plain-language cause, a primary Try again
/// that re-runs the controller's open path, and a secondary escape.
class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    super.key,
    required this.message,
    required this.controller,
  });

  final String message;
  final SessionController controller;

  Future<void> _retry() async {
    try {
      await controller.open(
          deviceId: controller.deviceId, mode: controller.mode);
    } catch (_) {
      // A repeated failure is recorded in the controller snapshot, which this
      // panel renders. Never throw out of a button callback.
    }
  }

  Future<void> _escape(BuildContext context) async {
    await controller.end();
    if (!context.mounted) return;
    await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = ThresholdSemanticColors.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            // One live region announcing the failure and its cause together, so
            // a screen reader user hears the whole situation, not a fragment.
            Semantics(
              container: true,
              liveRegion: true,
              label: '$message $kConnectionFailureCause',
              excludeSemantics: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.wifi_off_rounded,
                    size: Spacing.space9,
                    color: semantic.danger,
                  ),
                  const SizedBox(height: Spacing.space5),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: scheme.onSurface),
                  ),
                  const SizedBox(height: Spacing.space2),
                  Text(
                    kConnectionFailureCause,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.space6),
            Semantics(
              button: true,
              label: 'Try again',
              onTap: _retry,
              excludeSemantics: true,
              child: FilledButton.icon(
                key: const ValueKey('error-retry'),
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded, size: Spacing.space5),
                label: const Text('Try again'),
              ),
            ),
            const SizedBox(height: Spacing.space3),
            Semantics(
              button: true,
              label: 'Go back',
              onTap: () => _escape(context),
              excludeSemantics: true,
              child: TextButton.icon(
                key: const ValueKey('error-go-back'),
                onPressed: () => _escape(context),
                icon:
                    const Icon(Icons.arrow_back_rounded, size: Spacing.space5),
                label: const Text('Go back'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The single, non-destructive re-authentication prompt (FR-1.5, AT-12). There
/// is exactly one recovery path; the controller enforces one prompt at a time.
class _AuthRecoveryPrompt extends StatefulWidget {
  const _AuthRecoveryPrompt({required this.controller, this.authPort});
  final SessionController controller;
  final AuthPort? authPort;

  @override
  State<_AuthRecoveryPrompt> createState() => _AuthRecoveryPromptState();
}

class _AuthRecoveryPromptState extends State<_AuthRecoveryPrompt> {
  bool _signingIn = false;

  /// Run the real re-authentication flow (HIGH-09) and resume the session ONLY
  /// when a fresh token is verified. The old stub called
  /// completeAuthRecovery(success: true) unconditionally, resuming an expired
  /// session without re-authenticating. When no auth port is wired (headless
  /// caption tests) fall back to resolving recovery directly.
  Future<void> _signIn() async {
    if (_signingIn) return;
    final port = widget.authPort;
    if (port == null) {
      widget.controller.completeAuthRecovery(success: true);
      return;
    }
    setState(() => _signingIn = true);
    AuthResult result;
    try {
      result = await port.reauthenticate();
    } catch (_) {
      // A thrown binding is a failed re-authentication: do not resume.
      result = AuthResult.failed;
    }
    if (!mounted) return;
    setState(() => _signingIn = false);
    widget.controller
        .completeAuthRecovery(success: result == AuthResult.verified);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final controller = widget.controller;
    return Positioned.fill(
      // Block semantics and pointer traversal to everything beneath the modal
      // (MED-05): a screen reader could otherwise still reach End and Reply
      // behind the re-authentication prompt. BlockSemantics drops the subtree
      // below it in paint order from the semantics tree, and the opaque scrim
      // absorbs taps, so the prompt is genuinely modal.
      child: BlockSemantics(
        child: ColoredBox(
          // The themed scrim, replacing the raw 0xB3000000 (audit C2).
          color: scheme.scrim.withValues(alpha: kModalScrimOpacity),
          child: Center(
            child: Semantics(
              container: true,
              label: 'Sign in again to continue. Your conversation is saved.',
              child: Card(
                key: const ValueKey('auth-recovery-prompt'),
                margin: const EdgeInsets.all(Spacing.space6),
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.space5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.lock_person_outlined,
                        size: Spacing.space8,
                        color: scheme.primary,
                      ),
                      const SizedBox(height: Spacing.space4),
                      Text(
                        'Sign in again to continue',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(color: scheme.onSurface),
                      ),
                      const SizedBox(height: Spacing.space2),
                      Text(
                        'Your conversation is saved and will resume once you sign in.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: Spacing.space5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          TextButton(
                            key: const ValueKey('auth-recovery-cancel'),
                            onPressed: _signingIn
                                ? null
                                : () => controller.completeAuthRecovery(
                                    success: false),
                            child: const Text('Not now'),
                          ),
                          FilledButton(
                            key: const ValueKey('auth-recovery-signin'),
                            onPressed: _signingIn ? null : _signIn,
                            child: _signingIn
                                ? const SizedBox(
                                    width: Spacing.space5,
                                    height: Spacing.space5,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Text('Sign in'),
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
      ),
    );
  }
}
