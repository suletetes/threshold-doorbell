// Home screen and session routing (P2-1 composition root). The real entry
// surface: it lists the actions a resident takes (answer the door, open
// settings) and routes an incoming/started session to the Conversation screen
// (two-way) or the Captions-Only screen (receive-only) per the sticky outbound
// mode (FR-6.4, FR-12.4). Privacy Mode selection is gated by the model
// provisioning machine (FR-5.2a) via the session-start coordinator. Every
// control carries a Semantics label (G4). No dashes in any copy (NFR-10).
//
// Presentation (UI/UX audit C5, "the primary action has no visual weight", and
// section 4, "Information architecture"): this screen used to be a Column
// holding a paragraph of 18px text, a stock FilledButton, a helper line, and an
// OutlinedButton reading "Settings" that carried the same weight as the one
// action the product exists for. Three changes:
//
//   1. "Answer the door" is a PrimaryActionCard and is now the first and largest
//      thing on the screen.
//   2. Settings moved to an AppBar action. It is a destination, not a peer of
//      the hero.
//   3. The Privacy-Mode-unavailable line became a StatusBanner BELOW the hero
//      instead of a grey sentence wedged between the two buttons, so it no
//      longer interrupts the action group.
//
// Every color, size, radius, and spacing value comes from the design system
// (design principle 1: no literal in a screen).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../alerts/doorbell_alert_service.dart';
import '../captions/asr_client.dart';
import '../captions/language_selection.dart';
import '../captions/model_download_sheet.dart';
import '../captions/turn_segmentation.dart';
import '../consent/recording_notice.dart';
import '../consent/recording_notice_screen.dart';
import '../design/components/components.dart';
import '../design/tokens.dart';
import '../reply/reply_bar.dart';
import '../session/ringing_screen.dart';
import '../session/captions_only_screen.dart';
import '../session/conversation_screen.dart';
import '../session/session_controller.dart';
import '../session/session_state.dart';
import '../settings/settings_screen.dart';
import 'demo_debug_overlay.dart';
import 'mock_adapters.dart';
import 'providers.dart';

/// The device id used when a session is started from the home hero action with
/// no originating alert (MED-14). An alert-driven open supplies its own device
/// id; the alert path is deferred (CRIT-08).
const String kDefaultDeviceId = 'front-door';

/// What the hero action does, in one line under the label. Dash-free (NFR-10).
const String kHomeHeroSupportingLine =
    'Captions appear as your visitor speaks.';

/// The orienting copy, secondary to the action (recognition over recall: the
/// action comes first, the explanation second). Dash-free (NFR-10).
const String kHomeReadyExplanation =
    'Ready. When someone is at your door you can answer with '
    'captions, and reply out loud when two way audio is available.';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coordinator = ref.watch(sessionStartCoordinatorProvider);
    final theme = Theme.of(context);
    return DemoDebugOverlay(
      onRing: () => _showIncomingRing(context, ref),
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Threshold'),
        actions: <Widget>[
          // Settings is a destination, not a peer of the hero action (audit C5).
          Semantics(
            button: true,
            label: 'Open settings',
            onTap: () => _openSettings(context, ref),
            excludeSemantics: true,
            child: IconButton(
              key: const ValueKey('home-settings'),
              onPressed: () => _openSettings(context, ref),
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
            ),
          ),
          const SizedBox(width: Spacing.space2),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.space5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // The hero. Identifiable in under a second (design principle 6).
              PrimaryActionCard(
                key: const ValueKey('home-answer'),
                icon: Icons.doorbell_outlined,
                label: 'Answer the door',
                supportingText: kHomeHeroSupportingLine,
                semanticsLabel: 'Answer the door',
                onPressed: () => _startSession(context, ref),
              ),
              if (!coordinator.privacyModeAvailable) ...<Widget>[
                const SizedBox(height: Spacing.space4),
                // Out of the action group, and now one of the four shared
                // status treatments rather than a fifth ad hoc one.
                // The action opens the model download sheet so the resident
                // can immediately act on the unavailability (Task 18, FR-5.2a).
                StatusBanner(
                  message: coordinator.privacyUnavailableLabel,
                  messageKey: const ValueKey('home-privacy-unavailable'),
                  variant: StatusVariant.warning,
                  action: StatusBannerAction(
                    label: 'Set up',
                    icon: Icons.download_outlined,
                    buttonKey: const ValueKey('home-privacy-setup'),
                    semanticsLabel: 'Set up on device model download',
                    onPressed: () => showModelDownloadSheet(context),
                  ),
                ),
              ],
              const SizedBox(height: Spacing.space6),
              Text(
                kHomeReadyExplanation,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  /// Show the incoming-doorbell ring as a full-screen, call-style screen and
  /// route the resident's choice (FR-3.3). The phone is already buzzing and the
  /// call notification is showing (DoorbellAlertService, started by the demo
  /// overlay when the visitor rang); every path here stops that alert first.
  ///
  ///   Answer     -> open the captioned session.
  ///   I'm coming -> speak a line at the door, then open the session.
  ///   Decline    -> speak a polite line at the door and dismiss.
  ///   Missed     -> stop the alert and dismiss (the visitor's page times out).
  Future<void> _showIncomingRing(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsControllerProvider).settings;
    final replyPort = ref.read(replyPortProvider);

    Future<void> stopAlert() async {
      await DoorbellAlertService.shared.stopRing();
      // Clear the hub's ring dedupe flag so the NEXT doorbell press alerts
      // again (answer, decline, and missed all end this ring).
      if (DemoConfig.enabled) DemoHub.instance.resetRing();
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ringContext) => RingingScreen(
          strobeEnabled: settings.strobeEnabled,
          onAnswer: () async {
            await stopAlert();
            if (ringContext.mounted) Navigator.of(ringContext).pop();
            if (context.mounted) await _startSession(context, ref);
          },
          onComing: () async {
            await stopAlert();
            // Speak the coming line at the door (the demo reply port also relays
            // it to the visitor), then open the session.
            unawaited(replyPort.speak(kComingSpokenLine));
            if (ringContext.mounted) Navigator.of(ringContext).pop();
            if (context.mounted) await _startSession(context, ref);
          },
          onDecline: () async {
            await stopAlert();
            // Tell the visitor page the resident declined so it shows a clear
            // "Declined" state, and speak the polite line so they also hear it.
            if (DemoConfig.enabled) DemoHub.instance.sendDecline();
            unawaited(replyPort.speak(kDeclineSpokenLine));
            if (ringContext.mounted) Navigator.of(ringContext).pop();
          },
          onMissed: () async {
            await stopAlert();
            if (ringContext.mounted) Navigator.of(ringContext).pop();
          },
        ),
      ),
    );
  }

  Future<void> _startSession(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsControllerProvider);
    final coordinator = ref.read(sessionStartCoordinatorProvider);
    final notice = ref.read(recordingNoticeControllerProvider);

    // CRIT-06: enforce the first-run recording-consent gate BEFORE any live use.
    // Load the persisted acknowledgement, and if it has not been given, show the
    // one-time notice and block starting a session until the resident
    // acknowledges it (FR-14.1, AT-14). This was never called before: the gate
    // and mustAcknowledgeBeforeUse existed but nothing consulted them.
    await notice.load();
    if (notice.mustAcknowledgeBeforeUse) {
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RecordingNoticeScreen(
            controller: notice,
            onAcknowledged: () => Navigator.of(context).maybePop(),
          ),
        ),
      );
      // If the resident backed out without acknowledging, do not start a
      // session: the gate still blocks live use (FR-14.1).
      if (notice.mustAcknowledgeBeforeUse) return;
    }

    // Promote any pending mode change for the new session (FR-10.1).
    settings.applyPendingModeForNewSession();
    final requested = settings.settings.activeMode == CaptionMode.privacy
        ? SessionCaptionMode.privacy
        : SessionCaptionMode.clarity;

    // Resolve ONLY the mode gate here (Privacy availability, FR-5.2a). The
    // recording-notice/compliance decision depends on the real outbound
    // availability, which is not known until the capability probe runs inside
    // the session; it is resolved in _SessionHost AFTER the probe (CRIT-06),
    // not with a hard-coded outboundAvailable: true as before.
    final modePlan = coordinator.resolve(
      requestedMode: requested,
      // Conservative: assume outbound may be unavailable for the mode gate. The
      // notice action resolved here is discarded; the host re-resolves it with
      // the probed value.
      outboundAvailable: false,
    );

    if (!context.mounted) return;

    // Surface a refused Privacy Mode request instead of silently falling back
    // to Clarity while the badge or expectation says Privacy (MED-14). The
    // session runs in plan.mode (Clarity), and the resident is told why.
    if (modePlan.privacyRefused) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey('privacy-refused-notice'),
          content: Text(
            modePlan.privacyUnavailableLabel.isEmpty
                ? 'Privacy Mode is not ready yet. Starting in Clarity Mode.'
                : modePlan.privacyUnavailableLabel,
          ),
        ),
      );
    }

    // Route to the live session screen in the resolved mode (MED-14: use
    // plan.mode, not the requested mode). The deviceId comes from the alert
    // that opened the session; with the alert path deferred (CRIT-08) it
    // defaults to the resident's primary doorbell.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SessionHost(
          mode: modePlan.mode,
          deviceId: kDefaultDeviceId,
        ),
      ),
    );
  }

  Future<void> _openSettings(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsControllerProvider);
    // SettingsScreen builds its own Scaffold and AppBar. It used to be pushed
    // inside a second Scaffold with a second AppBar, which stacked two title
    // bars on top of each other.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(controller: settings),
      ),
    );
  }
}

/// Hosts the live session, opening it on first build and routing to the correct
/// screen per the sticky outbound mode. This is where alert -> conversation /
/// captions-only routing happens (FR-6.4, FR-12.4).
class _SessionHost extends ConsumerStatefulWidget {
  const _SessionHost({required this.mode, required this.deviceId});
  final SessionCaptionMode mode;

  /// The doorbell the session is for. Supplied by the alert that opened the
  /// session; defaults to the primary doorbell when started from the home hero
  /// action (MED-14). Replaces a hard-coded 'front-door'.
  final String deviceId;

  @override
  ConsumerState<_SessionHost> createState() => _SessionHostState();
}

class _SessionHostState extends ConsumerState<_SessionHost> {
  /// True once the user ended the session (via End or system back) so the idle
  /// transition pops this route exactly once instead of fighting an open() that
  /// is still settling (CRIT-05).
  bool _ending = false;

  /// True once the session has left idle at least once. Guards the idle-pop so
  /// the INITIAL idle (before the post-frame open() runs) does not pop the host
  /// before the session even starts (CRIT-05).
  bool _everStarted = false;

  /// The visitor text the current suggestions were produced for, so we do not
  /// re-request on every unrelated notification (FR-7.1a, MED-13).
  String? _suggestionsForText;

  /// True once the recording-notice/compliance decision has been resolved for
  /// this session using the real probe result (CRIT-06). Resolved exactly once,
  /// after the probe, so the hard-coded outboundAvailable:true is gone.
  bool _complianceResolved = false;

  /// Pumps live caption results from the ASR engine into the session controller
  /// (CRIT-07). Without this the caption surface never received a feed. Started
  /// in initState and stopped in dispose.
  CaptionPump? _captionPump;

  /// DEMO only: ends this session when the visitor hangs up from Phone A, so the
  /// resident is not stranded on a captions screen after the visitor leaves.
  StreamSubscription<void>? _demoHangupSub;

  @override
  void initState() {
    super.initState();
    // DEMO: when the visitor ends the call, end the resident session too.
    if (DemoConfig.enabled) {
      _demoHangupSub = DemoHub.instance.onHangup.listen((_) {
        if (mounted) _endAndLeave();
      });
    }
    // Attach the caption pump so live caption results reach the surface for this
    // session (CRIT-07). The controller drops results while idle/closed; the
    // pump just delivers the feed. The echo gate (FR-5.6) and the
    // transcription-disabled fallback (FR-14.3a) are enforced in ingestCaption.
    final controller = ref.read(sessionControllerProvider);
    final source = ref.read(captionSourceProvider);
    _captionPump = CaptionPump(controller: controller, source: source)..start();
    // Open the session after the first frame so a connect failure surfaces in
    // the controller snapshot rather than throwing during build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    final controller = ref.read(sessionControllerProvider);
    try {
      await controller.open(deviceId: widget.deviceId, mode: widget.mode);
    } on StateError {
      // A session is already active (concurrency rule, FR-4.6/4.7): the open was
      // refused. Do not re-show a stale session; leave the host (MED-14).
      if (mounted) _leave();
      return;
    }
    // Any connect/probe failure is recorded as ERROR in the controller snapshot
    // and rendered by the screen; it is not swallowed here (HIGH-04).

    // CRIT-06: the probe has now run, so the real outbound availability is
    // known. Resolve the recording-notice / compliance-fallback decision with
    // that real value (not the old hard-coded outboundAvailable: true) and
    // honour it: prompt the compliance fallback when required, and disable
    // transcription for the session when the resolved action says so.
    if (mounted) await _resolveComplianceAfterProbe();
  }

  /// Resolve and honour the FR-14.3a recording-notice action for this session
  /// using the probed outbound availability (CRIT-06). Runs once.
  Future<void> _resolveComplianceAfterProbe() async {
    if (_complianceResolved) return;
    final controller = ref.read(sessionControllerProvider);
    // Only resolve once the session actually reached a live state (the probe
    // ran). A failed connect/probe that ended in error or captions-only still
    // has a known outbound value; a connect failure (error) has no session to
    // transcribe, so skip it.
    if (controller.state == SessionState.error ||
        controller.state == SessionState.idle) {
      return;
    }
    _complianceResolved = true;

    final coordinator = ref.read(sessionStartCoordinatorProvider);
    final requested = widget.mode;
    final plan = coordinator.resolve(
      requestedMode: requested,
      outboundAvailable: controller.outboundAvailable,
    );

    // The resolved default already disables transcription or continues; honour
    // it directly (FR-14.3a).
    if (plan.transcriptionDisabled) {
      controller.transcriptionAllowed = false;
      return;
    }

    // The resident must be prompted (audible notice enabled, outbound
    // unavailable, no remembered default): show the compliance fallback dialog
    // and honour the returned choice (MED-06 returns a result).
    if (plan.mustPromptComplianceFallback) {
      if (!mounted) return;
      final notice = ref.read(recordingNoticeControllerProvider);
      final choice = await showDialog<ComplianceChoice>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ComplianceFallbackDialog(controller: notice),
      );
      if (choice == ComplianceChoice.disableTranscription) {
        controller.transcriptionAllowed = false;
      }
    }
  }

  /// End the session and leave the host route. Called from both the system back
  /// gesture (PopScope) and the controller returning to idle, so leaving the
  /// screen always tears the session down (CRIT-05): no peer connection, inbound
  /// audio or cloud transcription keeps running after the resident has left.
  Future<void> _endAndLeave() async {
    if (_ending) return;
    _ending = true;
    final controller = ref.read(sessionControllerProvider);
    try {
      await controller.end();
    } catch (_) {
      // end() must never block the user from leaving; the port is best effort.
    }
    _leave();
  }

  /// Request contextual suggestions for the latest final visitor turn when it
  /// changes (FR-7.1a, MED-13). Routed by the session mode through the
  /// suggestionProvider: Clarity consults Bedrock, Privacy stays on device.
  void _maybeRefreshSuggestions(SessionController controller) {
    final turns = controller.captionTurns;
    // The newest finalized visitor turn is what the suggestions respond to.
    String? latest;
    for (final turn in turns.reversed) {
      if (turn.speaker == CaptionSpeaker.visitor && turn.isFinal) {
        latest = turn.text.trim();
        break;
      }
    }
    if (latest == null || latest.isEmpty) return;
    if (latest == _suggestionsForText) {
      return; // already requested for this text
    }
    _suggestionsForText = latest;
    final provider = ref.read(suggestionProvider);
    final reply = ref.read(replyControllerProvider.notifier);
    final mode = controller.mode;
    unawaited(() async {
      try {
        final result = await provider.suggestionsFor(latest!, mode: mode);
        if (!mounted || _suggestionsForText != latest) return;
        // Set on the reply controller so the reply bar (which rebuilds on this
        // controller) repaints with the suggestions (FR-7.1a, MED-13).
        reply.setContextualSuggestions(result);
      } catch (_) {
        // A suggestion failure is non-fatal: the reply bar still shows the fixed
        // safe set. Leave the previous suggestions in place.
      }
    }());
  }

  /// Pop the host route now that the session is ending. canPop is already true
  /// (we set [_ending]), so this real pop is not re-intercepted by the PopScope.
  void _leave() {
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  @override
  void dispose() {
    // Stop pumping captions (CRIT-07); the source itself is owned by its
    // provider and disposed with the scope.
    unawaited(_captionPump?.stop());
    unawaited(_demoHangupSub?.cancel());
    // Leaving the host for any reason ends the session so nothing is left live
    // off screen (CRIT-05). Guard the read: if the ProviderScope is tearing
    // down with us, it has already disposed the controller (which closes the
    // port), and reading it here would throw.
    try {
      final controller = ref.read(sessionControllerProvider);
      unawaited(controller.end());
    } catch (_) {
      // Controller already disposed by the scope; its dispose() closed the port.
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(sessionControllerProvider);
    final settings = ref.watch(settingsControllerProvider).settings;
    final launcher = ref.watch(ringAppLauncherProvider);

    if (controller.state != SessionState.idle) _everStarted = true;

    // Refresh contextual suggestions when the latest final visitor turn changes
    // (FR-7.1a, MED-13).
    _maybeRefreshSuggestions(controller);

    // When the session returns to idle AFTER it started (the user tapped End, or
    // recovery was declined), pop back to a usable screen instead of stranding
    // the user on a blank media surface (CRIT-05). Scheduled post frame so we do
    // not navigate during build. Setting _ending flips PopScope.canPop so this
    // pop is not intercepted. The initial idle (before open()) is ignored.
    if (controller.state == SessionState.idle && _everStarted && !_ending) {
      _ending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _leave());
    }

    final Widget screen;
    // Route by the sticky outbound mode once probed (FR-6.4, FR-12.4).
    if (controller.isCaptionsOnly) {
      screen = CaptionsOnlyScreen(
        controller: controller,
        launcher: launcher,
        settings: settings,
      );
    } else {
      final replyController = ref.watch(replyControllerProvider);
      screen = ConversationScreen(
        controller: controller,
        settings: settings,
        authPort: ref.watch(authPortProvider),
        replyBar: ReplyBar(
          controller: replyController,
          // Contextual suggestions come from the controller (set by
          // _maybeRefreshSuggestions via the suggestion provider, FR-7.1a).
        ),
      );
    }

    // Intercept the system back gesture so it ends the session rather than
    // popping the route with the session still live behind it (CRIT-05). Once
    // we are ending, canPop is true so the real pop proceeds.
    return PopScope(
      canPop: _ending,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        _endAndLeave();
      },
      child: screen,
    );
  }
}
