// Home screen and session routing (P2-1 composition root). The real entry
// surface: it lists the actions a resident takes (answer the door, open
// settings) and routes an incoming/started session to the Conversation screen
// (two-way) or the Captions-Only screen (receive-only) per the sticky outbound
// mode (FR-6.4, FR-12.4). Privacy Mode selection is gated by the model
// provisioning machine (FR-5.2a) via the session-start coordinator. Every
// control carries a Semantics label (G4). No dashes in any copy (NFR-10).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../captions/language_selection.dart';
import '../reply/reply_bar.dart';
import '../session/captions_only_screen.dart';
import '../session/conversation_screen.dart';
import '../session/session_state.dart';
import '../settings/settings_screen.dart';
import 'providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coordinator = ref.watch(sessionStartCoordinatorProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Threshold')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                'Ready. When someone is at your door you can answer with '
                'captions, and reply out loud when two way audio is available.',
                style: TextStyle(fontSize: 18, height: 1.3),
              ),
              const SizedBox(height: 24),
              Semantics(
                button: true,
                label: 'Answer the door',
                excludeSemantics: true,
                child: FilledButton(
                  key: const ValueKey('home-answer'),
                  onPressed: () => _startSession(context, ref),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Answer the door'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (!coordinator.privacyModeAvailable)
                Semantics(
                  liveRegion: true,
                  label: coordinator.privacyUnavailableLabel,
                  child: Text(
                    coordinator.privacyUnavailableLabel,
                    key: const ValueKey('home-privacy-unavailable'),
                    style: const TextStyle(fontSize: 14, color: Color(0xFF555555)),
                  ),
                ),
              const SizedBox(height: 12),
              Semantics(
                button: true,
                label: 'Open settings',
                excludeSemantics: true,
                child: OutlinedButton(
                  key: const ValueKey('home-settings'),
                  onPressed: () => _openSettings(context, ref),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Settings'),
                  ),
                ),
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: SettingsScreen(controller: settings),
        ),
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

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(sessionControllerProvider);
    final settings = ref.watch(settingsControllerProvider).settings;
    final launcher = ref.watch(ringAppLauncherProvider);

    // Route by the sticky outbound mode once probed (FR-6.4, FR-12.4).
    if (controller.isCaptionsOnly) {
      return CaptionsOnlyScreen(
        controller: controller,
        launcher: launcher,
        settings: settings,
      );
    }
    final replyController = ref.watch(replyControllerProvider);
    return ConversationScreen(
      controller: controller,
      settings: settings,
      replyBar: ReplyBar(
        controller: replyController,
        contextualSuggestions: const <String>[],
      ),
    );
  }
}
