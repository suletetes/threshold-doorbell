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

import '../captions/language_selection.dart';
import '../design/components/components.dart';
import '../design/tokens.dart';
import '../reply/reply_bar.dart';
import '../session/captions_only_screen.dart';
import '../session/conversation_screen.dart';
import '../session/session_state.dart';
import '../settings/settings_screen.dart';
import 'providers.dart';

/// What the hero action does, in one line under the label. Dash-free (NFR-10).
const String kHomeHeroSupportingLine = 'Captions appear as your visitor speaks.';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Threshold'),
        actions: <Widget>[
          // Settings is a destination, not a peer of the hero action (audit C5).
          Semantics(
            button: true,
            label: 'Open settings',
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
                StatusBanner(
                  message: coordinator.privacyUnavailableLabel,
                  messageKey: const ValueKey('home-privacy-unavailable'),
                  variant: StatusVariant.warning,
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
    );
  }

  Future<void> _startSession(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsControllerProvider);
    final coordinator = ref.read(sessionStartCoordinatorProvider);

    // Promote any pending mode change for the new session (FR-10.1).
    settings.applyPendingModeForNewSession();
    final requested = settings.settings.activeMode == CaptionMode.privacy
        ? SessionCaptionMode.privacy
        : SessionCaptionMode.clarity;

    // Consult the model-provisioning gate + recording-notice fallback. The
    // probe result is not known until connect; resolve conservatively assuming
    // outbound may be unavailable so the fallback is honored.
    final plan = coordinator.resolve(
      requestedMode: requested,
      outboundAvailable: true,
    );

    if (!context.mounted) return;
    // Route to the live session screen. The screen renders from the controller
    // snapshot; the reply bar hides itself when outbound is unavailable.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SessionHost(mode: plan.mode),
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
  const _SessionHost({required this.mode});
  final SessionCaptionMode mode;

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

  @override
  void initState() {
    super.initState();
    // Open the session after the first frame so a connect failure surfaces in
    // the controller snapshot rather than throwing during build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    final controller = ref.read(sessionControllerProvider);
    try {
      await controller.open(deviceId: 'front-door', mode: widget.mode);
    } catch (_) {
      // The controller records ERROR in its snapshot; the screen renders it.
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

  /// Pop the host route now that the session is ending. canPop is already true
  /// (we set [_ending]), so this real pop is not re-intercepted by the PopScope.
  void _leave() {
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  @override
  void dispose() {
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
        replyBar: ReplyBar(
          controller: replyController,
          contextualSuggestions: const <String>[],
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
