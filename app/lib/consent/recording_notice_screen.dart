// First-run recording-notice screen (Task 21, FR-14.1; AT-14). A one-time gate
// shown before the first live use: the plain-language notice plus a single
// acknowledgement action. Also reachable from Settings. Fully accessible (G4).
//
// --- Presentation (UI/UX audit section 5) -----------------------------------
//
// This was a raw fontSize of 18 with a raw height of 1.4 and a stock FilledButton
// at the bottom of a bare Column. It now uses the design system: a SectionHeader
// naming what the notice is about, the notice copy on the type scale, and the
// acknowledgement as a hero action, because acknowledging IS the only thing this
// screen asks for and the audit's design principle 6 says the hero action should
// be identifiable in under a second.
//
// The compliance fallback dialog gets the same treatment: an icon carrying the
// meaning, and the two choices weighted so the less destructive one reads as the
// default.

import 'package:flutter/material.dart';

import '../design/colors.dart';
import '../design/components/components.dart';
import '../design/tokens.dart';
import 'recording_notice.dart';
import 'recording_notice_controller.dart';

/// The heading over the recording notice. Dash-free (NFR-10).
const String kRecordingNoticeHeading = 'How captions work';

class RecordingNoticeScreen extends StatelessWidget {
  const RecordingNoticeScreen({
    super.key,
    required this.controller,
    this.onAcknowledged,
  });

  final RecordingNoticeController controller;
  final VoidCallback? onAcknowledged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Before you start')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.space5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SectionHeader(title: kRecordingNoticeHeading),
              Expanded(
                child: SingleChildScrollView(
                  child: Semantics(
                    liveRegion: true,
                    label: kRecordingNoticeText,
                    excludeSemantics: true,
                    child: Text(
                      kRecordingNoticeText,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.space5),
              // Acknowledging is the only thing this screen asks for, so it is
              // the hero action rather than a stock button at the bottom.
              PrimaryActionCard(
                key: const ValueKey('recording-notice-ack'),
                icon: Icons.check_circle_outline,
                label: 'I understand',
                supportingText: 'You can read this again in Settings.',
                semanticsLabel: 'I understand',
                onPressed: () async {
                  await controller.acknowledge();
                  onAcknowledged?.call();
                },
              ),
              const SizedBox(height: Spacing.space5),
            ],
          ),
        ),
      ),
    );
  }
}

/// The FR-14.3a compliance-fallback prompt: continue without the audible notice,
/// or disable transcription for this session. Shown when the audible notice is
/// enabled but outbound audio is unavailable and no default is remembered.
///
/// MED-06: the dialog now POPS with the chosen [ComplianceChoice] (previously it
/// never closed), and the "remember my choice" option is an explicit checkbox
/// that defaults to OFF, so a one-time per-session choice does not silently
/// become the persisted legal default. The checkbox value is passed through to
/// the controller as [rememberAsDefault].
class ComplianceFallbackDialog extends StatefulWidget {
  const ComplianceFallbackDialog({super.key, required this.controller});

  final RecordingNoticeController controller;

  @override
  State<ComplianceFallbackDialog> createState() => _ComplianceFallbackDialogState();
}

class _ComplianceFallbackDialogState extends State<ComplianceFallbackDialog> {
  /// Defaults OFF (MED-06): remembering a legal choice must be opt in.
  bool _remember = false;

  Future<void> _choose(ComplianceChoice choice) async {
    await widget.controller.chooseComplianceFallback(
      choice,
      rememberAsDefault: _remember,
    );
    if (!mounted) return;
    // Close the dialog with its result (MED-06). maybePop is safe whether the
    // dialog was pushed as a route (showDialog) or rendered inline in a test.
    Navigator.of(context).maybePop(choice);
  }

  @override
  Widget build(BuildContext context) {
    final semantic = ThresholdSemanticColors.of(context);
    return AlertDialog(
      key: const ValueKey('compliance-fallback'),
      icon: Icon(
        Icons.volume_off_outlined,
        color: semantic.warning,
        size: Spacing.space8,
      ),
      title: const Text('Spoken door notice unavailable'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'This device cannot play the spoken notice at the door for this '
            'session. Choose how to continue.',
          ),
          const SizedBox(height: Spacing.space3),
          // Explicit, default-off remember toggle (MED-06).
          Semantics(
            toggled: _remember,
            label: 'Remember my choice for future sessions',
            child: CheckboxListTile(
              key: const ValueKey('compliance-remember'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _remember,
              onChanged: (v) => setState(() => _remember = v ?? false),
              title: const Text('Remember my choice for future sessions'),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          key: const ValueKey('compliance-disable-transcription'),
          onPressed: () => _choose(ComplianceChoice.disableTranscription),
          child: const Text('Turn off captions this session'),
        ),
        FilledButton(
          key: const ValueKey('compliance-continue'),
          onPressed: () => _choose(ComplianceChoice.continueWithoutNotice),
          child: const Text('Continue with captions'),
        ),
      ],
    );
  }
}
