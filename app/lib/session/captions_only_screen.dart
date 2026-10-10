// Captions-Only screen (Task 17, FR-12.1..FR-12.4, N9; AT-6, AT-10). A
// receive-only conversation screen: live captions of the visitor, video, alerts,
// and history all work; only spoken replies are unavailable, so there is NO
// reply bar. A persistent, non-alarming banner states the situation, and a
// one-tap "Open Ring app" action lets a hearing household member respond
// (FR-12.3). There is no visitor-facing prompt (N9). Captions-Only is a
// first-class mode, not an error state (FR-12.4), so it renders the same live
// video + caption layout as the two-way screen, minus the reply bar.
//
// --- Presentation (UI/UX audit section 3.6 and C2) --------------------------
//
// The banner was one of the four ad hoc "status message" treatments the audit
// found: a hand-rolled Container with a 0xFF2A3A4A fill picked by eye, a raw
// radius of 12, a raw fontSize of 16, and an OutlinedButton with hardcoded white
// borders. It is now the shared StatusBanner in the `warning` variant, which is
// the right semantic for FR-12.4: a degraded but fully usable mode, not an error.
// The exact FR-12.2 copy and the FR-12.3 action are unchanged; the action gained
// an icon and real filled-button weight, as the audit asked for by name.
//
// The scaffold and the video placeholder now come from the media surface theme
// shared with the conversation screen, so 0xFF0B0B0F and 0xFF15151B are gone.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../captions/caption_announcer.dart';
import '../captions/caption_surface.dart';
import '../design/colors.dart';
import '../design/components/components.dart';
import '../design/tokens.dart';
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

  /// The session states Captions-Only renders its own receive-only layout for.
  /// Every other state (connecting, probing, reconnecting, error, closing, auth
  /// recovery, idle) is delegated to the shared conversation screen state
  /// switcher so Captions-Only is not stuck showing the live layout in every
  /// state and does not stay up after End (MED-07).
  static const Set<SessionState> _ownLayoutStates = <SessionState>{
    SessionState.live,
    SessionState.backgrounded,
  };

  @override
  Widget build(BuildContext context) {
    return Theme(
      // The same media surface theme as the two-way screen: Captions-Only is a
      // first-class mode (FR-12.4), so it must not look like a different app.
      data: mediaSurfaceTheme(),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => _build(context, controller.snapshot),
      ),
    );
  }

  Widget _build(BuildContext context, SessionSnapshot snap) {
    // Share the conversation screen's error/reconnecting/auth/idle switcher for
    // every state other than the live receive-only ones (MED-07). The reply bar
    // stays absent, so this remains Captions-Only; only the transient and
    // terminal states are handled consistently with the two-way screen.
    if (!_ownLayoutStates.contains(snap.state)) {
      return ConversationScreen(
        controller: controller,
        settings: _settings,
        videoSurfaceBuilder: videoSurfaceBuilder,
      );
    }
    return _liveBuild(context, snap);
  }

  Widget _liveBuild(BuildContext context, SessionSnapshot snap) {
    final builder = videoSurfaceBuilder ?? defaultVideoSurface;
    final semantic = ThresholdSemanticColors.of(context);
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: semantic.captionSurface,
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
                child: isLandscape ? _landscape(context) : _portrait(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _portrait(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _banner(context),
        // Caption region: the visitor's speech, receive-only (FR-12.1).
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              Flexible(child: _captionRegion()),
            ],
          ),
        ),
        // NO reply bar in Captions-Only Mode (FR-12.1).
        _endControl(),
      ],
    );
  }

  /// Landscape: the banner and the end control stay on the left, captions get a
  /// full height column on the right (audit section 4, "Responsive and
  /// adaptive"). Captions-Only is the mode most likely to be read from a propped
  /// up phone, because the resident cannot reply from it at all.
  Widget _landscape(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _banner(context),
              const Spacer(),
              _endControl(),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(
              right: Spacing.space3,
              bottom: Spacing.space3,
            ),
            child: _captionRegion(fillHeight: true),
          ),
        ),
      ],
    );
  }

  Widget _banner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.space3),
      child: StatusBanner(
        key: const ValueKey('captions-only-banner'),
        // Non-alarming and not an error: a degraded but usable mode (FR-12.2,
        // FR-12.4).
        variant: StatusVariant.warning,
        icon: Icons.mic_off_outlined,
        message: kCaptionsOnlyBanner,
        action: StatusBannerAction(
          label: 'Open Ring app',
          icon: Icons.open_in_new,
          buttonKey: const ValueKey('open-ring-app'),
          onPressed: () => _openRingApp(context),
        ),
      ),
    );
  }

  /// Open the Ring app, honoring the launch result (MED-07). The old code
  /// discarded the result, so an "app not installed" outcome was silently
  /// ignored. When the app cannot be launched the resident is told to install
  /// it from the store (the store fallback), via a dash-free snackbar.
  Future<void> _openRingApp(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    bool launched;
    try {
      launched = await launcher.openRingApp();
    } catch (_) {
      launched = false;
    }
    if (launched) return;
    messenger.showSnackBar(
      const SnackBar(
        key: ValueKey('ring-app-fallback'),
        content: Text(
          'The Ring app is not installed. Please install it from your app store '
          'to reply by voice.',
        ),
      ),
    );
  }

  Widget _captionRegion({bool fillHeight = false}) {
    return Padding(
      padding: fillHeight
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: Spacing.space3),
      child: _CaptionsOnlyRegion(
        controller: controller,
        settings: _settings,
        fillHeight: fillHeight,
      ),
    );
  }

  Widget _endControl() {
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
            key: const ValueKey('captions-only-end'),
            onPressed: () => controller.end(),
            icon: const Icon(Icons.call_end_rounded, size: Spacing.space5),
            label: const Text('End'),
          ),
        ),
      ),
    );
  }
}

/// The caption container for the receive-only surface. Same treatment as the
/// two-way screen so the two modes read as one product (FR-12.4): the resident's
/// caption background composited over the `captionSurface` role, which is opaque
/// so inbound video cannot bleed through the surface the 4.5:1 floor was computed
/// against (FR-10.2, NFR-2).
class _CaptionsOnlyRegion extends StatefulWidget {
  const _CaptionsOnlyRegion({
    required this.controller,
    required this.settings,
    required this.fillHeight,
  });

  final SessionController controller;
  final ThresholdSettings settings;
  final bool fillHeight;

  @override
  State<_CaptionsOnlyRegion> createState() => _CaptionsOnlyRegionState();
}

class _CaptionsOnlyRegionState extends State<_CaptionsOnlyRegion> {
  final CaptionAnnouncer _announcer = CaptionAnnouncer();

  @override
  Widget build(BuildContext context) {
    final semantic = ThresholdSemanticColors.of(context);
    final scheme = Theme.of(context).colorScheme;

    // Announce each newly finalized turn once, throttled, rather than marking
    // the whole container as a live region (LOW-09).
    final announcement = _announcer.announcementFor(widget.controller.captionTurns);
    if (announcement != null) {
      final view = View.of(context);
      final direction = Directionality.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        SemanticsService.sendAnnouncement(view, announcement, direction);
      });
    }

    return Semantics(
      label: 'Visitor captions',
      child: Container(
        key: const ValueKey('captions-only-region'),
        constraints: widget.fillHeight
            ? null
            : const BoxConstraints(minHeight: kCaptionRegionMinHeight),
        padding: const EdgeInsets.all(Spacing.space4),
        decoration: BoxDecoration(
          color: Color.alphaBlend(widget.settings.captionBackground, semantic.captionSurface),
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
        // Real caption turns with confidence emphasis + the enforced
        // accessibility settings (FR-5.3/5.3a, FR-10.2, NFR-2; AT-4, AT-9).
        child: SingleChildScrollView(
          reverse: true,
          child: CaptionSurface(
            turns: widget.controller.captionTurns,
            settings: widget.settings,
          ),
        ),
      ),
    );
  }
}
