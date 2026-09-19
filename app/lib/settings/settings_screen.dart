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

import 'package:flutter/material.dart';

import '../alerts/haptic_vocabulary.dart';
import '../captions/language_selection.dart';
import 'settings_controller.dart';
import 'settings_state.dart';

/// Plain-language Privacy-Mode explanation (FR-10.1, design §8.5). Dash-free.
const String kPrivacyModeExplanation =
    'Privacy Mode keeps everything on your phone. Captions are made on device '
    'and cloud suggestions are not used. Clarity Mode uses the cloud for the '
    'most accurate captions and short suggested replies.';

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
      maxScaleFactor: 2.0,
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
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _section('Caption mode'),
          Semantics(
            label: 'Privacy Mode explanation',
            child: const Text(kPrivacyModeExplanation),
          ),
          _ModeSwitch(controller: controller, settings: s),
          const Divider(),

          _section('Caption size'),
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
          const Divider(),

          _section('Caption contrast'),
          Semantics(
            liveRegion: true,
            label: 'Caption contrast ratio '
                '${s.captionContrastRatio.toStringAsFixed(1)} to 1. '
                'The minimum is 4.5 to 1.',
            child: Text(
              key: const ValueKey('contrast-readout'),
              'Contrast ${s.captionContrastRatio.toStringAsFixed(1)} to 1 '
              '(minimum 4.5 to 1)',
            ),
          ),
          const Divider(),

          _section('Alerts'),
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
          const Divider(),

          _section('Recognition language'),
          Semantics(
            label: 'Recognition language, currently ${s.language}',
            child: Text(
              key: const ValueKey('language-readout'),
              'Language: ${s.language}',
            ),
          ),
          const Divider(),

          _section('Data'),
          Semantics(
            label: s.retentionLabel,
            child: Text(key: const ValueKey('retention-readout'), s.retentionLabel),
          ),
          const SizedBox(height: 12),
          Semantics(
            button: true,
            label: 'Delete all my data',
            excludeSemantics: true,
            child: FilledButton.tonal(
              key: const ValueKey('delete-all-data'),
              style: FilledButton.styleFrom(
                foregroundColor: const Color(0xFFB00020),
              ),
              onPressed: () => _confirmDelete(context),
              child: const Text('Delete all my data'),
            ),
          ),
          const Divider(),

          _section('Haptic reference'),
          for (final pattern in HapticVocabulary.all)
            Semantics(
              label: 'Haptic pattern: ${pattern.label}',
              child: ListTile(
                key: ValueKey('haptic-ref-${pattern.event.name}'),
                title: Text(pattern.label),
                trailing: Text('${pattern.totalDurationMs} ms'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Semantics(
          header: true,
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
      );

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('delete-confirm-dialog'),
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
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    await controller.deleteAllMyData(confirmed: confirmed ?? false);
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.controller, required this.settings});
  final SettingsController controller;
  final ThresholdSettings settings;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Semantics(
          toggled: settings.pendingMode == CaptionMode.privacy,
          label: 'Privacy Mode. Applies to your next session.',
          child: SwitchListTile(
            key: const ValueKey('mode-switch'),
            title: const Text('Privacy Mode'),
            subtitle: const Text('Applies to your next session.'),
            value: settings.pendingMode == CaptionMode.privacy,
            onChanged: (v) => controller.requestModeChange(
              v ? CaptionMode.privacy : CaptionMode.clarity,
            ),
          ),
        ),
        if (settings.pendingMode != settings.activeMode)
          Semantics(
            liveRegion: true,
            label: 'The mode change applies to your next session.',
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'The mode change applies to your next session.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
          ),
      ],
    );
  }
}
