// First-run recording-notice screen (Task 21, FR-14.1; AT-14). A one-time gate
// shown before the first live use: the plain-language notice plus a single
// acknowledgement action. Also reachable from Settings. Fully accessible (G4).

import 'package:flutter/material.dart';

import 'recording_notice.dart';
import 'recording_notice_controller.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Before you start')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              liveRegion: true,
              label: kRecordingNoticeText,
              excludeSemantics: true,
              child: const Text(
                kRecordingNoticeText,
                style: TextStyle(fontSize: 18, height: 1.4),
              ),
            ),
            const Spacer(),
            Semantics(
              button: true,
              label: 'I understand',
              excludeSemantics: true,
              child: FilledButton(
                key: const ValueKey('recording-notice-ack'),
                onPressed: () async {
                  await controller.acknowledge();
                  onAcknowledged?.call();
                },
                child: const Text('I understand'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The FR-14.3a compliance-fallback prompt: continue without the audible notice,
/// or disable transcription for this session. Shown when the audible notice is
/// enabled but outbound audio is unavailable and no default is remembered.
class ComplianceFallbackDialog extends StatelessWidget {
  const ComplianceFallbackDialog({super.key, required this.controller});

  final RecordingNoticeController controller;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('compliance-fallback'),
      title: const Text('Spoken door notice unavailable'),
      content: const Text(
        'This device cannot play the spoken notice at the door for this '
        'session. Choose how to continue.',
      ),
      actions: <Widget>[
        TextButton(
          key: const ValueKey('compliance-disable-transcription'),
          onPressed: () => controller.chooseComplianceFallback(
            ComplianceChoice.disableTranscription,
          ),
          child: const Text('Turn off captions this session'),
        ),
        FilledButton(
          key: const ValueKey('compliance-continue'),
          onPressed: () => controller.chooseComplianceFallback(
            ComplianceChoice.continueWithoutNotice,
          ),
          child: const Text('Continue with captions'),
        ),
      ],
    );
  }
}
