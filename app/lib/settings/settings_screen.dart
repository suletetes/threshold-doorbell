// Settings screen (Task 24, FR-8.5, FR-8.6, FR-10.1..FR-10.4, FR-14.1, NFR-2;
// AT-9). WCAG 2.2 AA: every interactive element carries a Semantics label, the
// screen honors OS text scaling to 200% (MediaQuery textScaler), and the caption
// contrast floor is enforced in the model. Sections: mode switch with a plain
// Privacy-Mode explanation; caption size and contrast; per-pattern haptic
// toggles; strobe off by default; language; retention display; "Delete all my
// data" behind a confirmation; recording-notice text; haptic reference.
//
// A real screen-reader (TalkBack / VoiceOver) pass is a device-only step and is
// deferred to the developer's machine; the Semantics tree asserted by the widget
// tests is the headless proxy for it here.
//
// --- Presentation (UI/UX audit section 4) -----------------------------------
//
// "Settings is a flat list with no grouping hierarchy, despite containing mode,
// captions, haptics, strobe, language, retention, erasure, and the recording
// notice. That is at least four distinct concerns." It is now four groups with
// SectionHeader (Captions, Alerts, Language, Privacy and data), with the haptic
// reference as a subordinate dense header inside Alerts. Every control and every
// Semantics label is unchanged; only the order and the grouping moved.
//
// "Delete all my data" now reads as destructive: it carries the `danger` semantic
// role instead of a 0xFFB00020 literal picked by hand, and the confirm action in
// its dialog does too.
//
// The inline `_section` helper, with its raw fontSize of 18 and raw w700, is gone.

import 'package:flutter/material.dart';

import '../alerts/haptic_vocabulary.dart';
import '../captions/language_selection.dart';
import '../design/colors.dart';
import '../design/components/components.dart';
import '../design/tokens.dart';
import 'settings_controller.dart';
import 'settings_state.dart';

/// Plain-language Privacy-Mode explanation (FR-10.1, design §8.5). Dash-free.
const String kPrivacyModeExplanation =
    'Privacy Mode keeps everything on your phone. Captions are made on device '
    'and cloud suggestions are not used. Clarity Mode uses the cloud for the '
    'most accurate captions and short suggested replies.';

/// The maximum OS text scale this screen honors (NFR-2): 200%.
const double kMaxSettingsTextScale = 2.0;

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    // Honor OS text scaling up to 200% (NFR-2). We clamp so extreme system
    // scaling does not exceed the tested 200% ceiling while never shrinking.
    final media = MediaQuery.of(context);
    final scaler = media.textScaler.clamp(
      minScaleFactor: 1.0,
      maxScaleFactor: kMaxSettingsTextScale,
    );
    return MediaQuery(
      data: media.copyWith(textScaler: scaler),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => _build(context, controller.settings),
      ),
    );
  }

  Widget _build(BuildContext context, ThresholdSettings s) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = ThresholdSemanticColors.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.space4,
          vertical: Spacing.space2,
        ),
        children: <Widget>[
          // --- Captions -------------------------------------------------------
          const SectionHeader(
            title: 'Captions',
            supportingText: 'How captions are made, how big they are, and how '
                'much they stand out.',
          ),
          Semantics(
            label: 'Privacy Mode explanation',
            child: Text(
              kPrivacyModeExplanation,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: Spacing.space2),
          _ModeSwitch(controller: controller, settings: s),

          const SectionHeader(title: 'Caption size', dense: true),
          Semantics(
            slider: true,
            label: 'Caption text size',
            value: '${(s.captionScale * 100).round()} percent',
            child: Slider(
              key: const ValueKey('caption-scale'),
              min: kMinCaptionScale,
              max: kMaxCaptionScale,
              divisions: 10,
              value: s.captionScale,
              label: '${(s.captionScale * 100).round()}%',
              onChanged: controller.setCaptionScale,
            ),
          ),

          const SectionHeader(title: 'Caption contrast', dense: true),
          Semantics(
            liveRegion: true,
            label: 'Caption contrast ratio '
                '${s.captionContrastRatio.toStringAsFixed(1)} to 1. '
                'The minimum is 4.5 to 1.',
            child: Text(
              key: const ValueKey('contrast-readout'),
              'Contrast ${s.captionContrastRatio.toStringAsFixed(1)} to 1 '
              '(minimum 4.5 to 1)',
              style: theme.textTheme.bodyMedium,
            ),
          ),

          // --- Alerts ---------------------------------------------------------
          const SectionHeader(
            title: 'Alerts',
            supportingText: 'How your phone tells you someone is at the door.',
          ),
          for (final pattern in HapticVocabulary.all)
            Semantics(
              toggled: s.hapticEnabled[pattern.event] ?? true,
              label: 'Haptic: ${pattern.label}',
              child: SwitchListTile(
                key: ValueKey('haptic-${pattern.event.name}'),
                title: Text(pattern.label),
                value: s.hapticEnabled[pattern.event] ?? true,
                onChanged: (v) => controller.setHapticEnabled(pattern.event, v),
              ),
            ),
          Semantics(
            toggled: s.strobeEnabled,
            label: 'Screen strobe and torch alert',
            child: SwitchListTile(
              key: const ValueKey('strobe-toggle'),
              title: const Text('Screen strobe and torch'),
              subtitle: const Text('Off by default. Capped at 3 flashes per second.'),
              value: s.strobeEnabled,
              onChanged: controller.setStrobeEnabled,
            ),
          ),
          const SectionHeader(title: 'Haptic reference', dense: true),
          for (final pattern in HapticVocabulary.all)
            Semantics(
              label: 'Haptic pattern: ${pattern.label}',
              child: ListTile(
                key: ValueKey('haptic-ref-${pattern.event.name}'),
                title: Text(pattern.label),
                trailing: Text('${pattern.totalDurationMs} ms'),
              ),
            ),

          // --- Language -------------------------------------------------------
          const SectionHeader(
            title: 'Language',
            supportingText: 'The language captions are recognized in.',
          ),
          Semantics(
            label: 'Recognition language, currently ${s.language}',
            child: Text(
              key: const ValueKey('language-readout'),
              'Language: ${s.language}',
              style: theme.textTheme.bodyMedium,
            ),
          ),

          // --- Privacy and data -----------------------------------------------
          const SectionHeader(
            title: 'Privacy and data',
            supportingText: 'What is kept, for how long, and how to erase it.',
          ),
          Semantics(
            label: s.retentionLabel,
            child: Text(
              key: const ValueKey('retention-readout'),
              s.retentionLabel,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: Spacing.space4),
          Semantics(
            button: true,
            label: 'Delete all my data',
            onTap: controller.erasureInFlight ? null : () => _confirmDelete(context),
            excludeSemantics: true,
            child: FilledButton.tonalIcon(
              key: const ValueKey('delete-all-data'),
              // The danger role, replacing a 0xFFB00020 literal. Destructive
              // actions should look destructive before they are pressed, not
              // only in the dialog that follows.
              style: FilledButton.styleFrom(
                foregroundColor: semantic.danger,
                backgroundColor: Color.alphaBlend(
                  semantic.danger.withValues(alpha: 0.12),
                  scheme.surfaceContainerHigh,
                ),
                side: BorderSide(
                  color: semantic.danger.withValues(alpha: 0.45),
                  width: 1.5,
                ),
              ),
              // Disabled while an erasure is in flight so it cannot be
              // double-submitted (HIGH-08).
              onPressed: controller.erasureInFlight ? null : () => _confirmDelete(context),
              icon: controller.erasureInFlight
                  ? const SizedBox(
                      key: ValueKey('delete-in-flight'),
                      width: Spacing.space5,
                      height: Spacing.space5,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline, size: Spacing.space5),
              label: Text(controller.erasureInFlight ? 'Deleting your data' : 'Delete all my data'),
            ),
          ),
          // The result of the last erasure: a success or failure banner, with a
          // retry on failure. The privacy-critical action no longer silently
          // does nothing or throws out of the callback (HIGH-08).
          if (controller.erasureStatus == ErasureStatus.success) ...<Widget>[
            const SizedBox(height: Spacing.space3),
            StatusBanner(
              key: const ValueKey('delete-success-banner'),
              variant: StatusVariant.success,
              icon: Icons.check_circle_outline,
              message: 'Your data was deleted and your Ring connection was revoked.',
              action: StatusBannerAction(
                label: 'Dismiss',
                buttonKey: const ValueKey('delete-banner-dismiss'),
                onPressed: controller.dismissErasureStatus,
              ),
            ),
          ] else if (controller.erasureStatus == ErasureStatus.failure) ...<Widget>[
            const SizedBox(height: Spacing.space3),
            StatusBanner(
              key: const ValueKey('delete-failure-banner'),
              variant: StatusVariant.danger,
              icon: Icons.error_outline,
              message: 'We could not delete your data. Please try again.',
              action: StatusBannerAction(
                label: 'Try again',
                buttonKey: const ValueKey('delete-retry'),
                onPressed: _retryDelete,
              ),
            ),
          ],
          const SizedBox(height: Spacing.space7),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final semantic = ThresholdSemanticColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('delete-confirm-dialog'),
        icon: Icon(Icons.warning_amber_rounded, color: semantic.danger, size: Spacing.space8),
        title: const Text('Delete all your data'),
        content: const Text(
          'This erases all your transcripts and revokes your Ring connection. '
          'This cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            key: const ValueKey('delete-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('delete-confirm'),
            // The destructive action carries the danger role through to the
            // confirmation, so the weight of the choice is consistent.
            style: FilledButton.styleFrom(
              backgroundColor: semantic.danger,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    // The result drives the controller's erasureStatus, which the screen
    // renders as a success or failure banner (HIGH-08). No value is discarded.
    await controller.deleteAllMyData(confirmed: confirmed ?? false);
  }

  /// Retry a failed erasure. The resident already confirmed the destructive
  /// action, so a retry re-attempts it directly (HIGH-08).
  Future<void> _retryDelete() async {
    await controller.deleteAllMyData(confirmed: true);
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.controller, required this.settings});
  final SettingsController controller;
  final ThresholdSettings settings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          toggled: settings.pendingMode == CaptionMode.privacy,
          label: 'Privacy Mode. Applies to your next session.',
          child: SwitchListTile(
            key: const ValueKey('mode-switch'),
            title: const Text('Privacy Mode'),
            subtitle: const Text('Applies to your next session.'),
            secondary: const Icon(Icons.lock_outline),
            value: settings.pendingMode == CaptionMode.privacy,
            onChanged: (v) => controller.requestModeChange(
              v ? CaptionMode.privacy : CaptionMode.clarity,
            ),
          ),
        ),
        if (settings.pendingMode != settings.activeMode)
          const Padding(
            padding: EdgeInsets.only(top: Spacing.space2),
            child: StatusBanner(
              key: ValueKey('mode-pending-notice'),
              message: 'The mode change applies to your next session.',
              icon: Icons.schedule_outlined,
            ),
          ),
      ],
    );
  }
}
