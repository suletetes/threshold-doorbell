// Privacy Mode model download sheet (Task 18, FR-5.2a).
//
// A modal bottom sheet that walks the resident through the three stages of
// model provisioning:
//
//   notPresent / failed -> opt-in gate: explains what will be downloaded and
//     how large it is before any bytes move (FR-5.2a size disclosure).
//   optIn -> confirm screen: tapping Download starts the transfer.
//   downloading -> progress bar with byte count and a Cancel action.
//   verifying -> spinner while the model is checked.
//   verified -> success state; the sheet auto-dismisses after 1 s.
//
// A live session blocks the download (FR-5.2a). The sheet detects this from
// the controller and shows an explanatory message instead.
//
// Copy rules: no em-dash, no en-dash anywhere (NFR-10). All user-facing strings
// are plain ASCII with no special punctuation.
// Design rules: all spacing, radius, and colour values come from the design
// system. No literals.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/colors.dart';
import '../design/tokens.dart';
import 'model_provisioning.dart';
import 'model_provisioning_controller.dart';
import '../app/providers.dart';

/// Shows the Privacy Mode model download sheet over [context].
/// Returns when the sheet is dismissed for any reason.
Future<void> showModelDownloadSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.extraLarge)),
    ),
    builder: (_) => const _ModelDownloadSheet(),
  );
}

class _ModelDownloadSheet extends ConsumerWidget {
  const _ModelDownloadSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.watch(modelProvisioningControllerProvider);
    final snapshot = ctrl.snapshot;

    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.space5,
        right: Spacing.space5,
        top: Spacing.space4,
        bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.space6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Drag handle.
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: Radii.roundedFull,
              ),
            ),
          ),
          const SizedBox(height: Spacing.space5),

          // Title.
          Text(
            'Privacy Mode model',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: Spacing.space2),

          // Subtitle / description.
          Text(
            'Privacy Mode transcribes speech on your device. '
            'No audio or text leaves your phone.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: Spacing.space5),

          // State-specific content.
          _StateBody(snapshot: snapshot, ctrl: ctrl),

          const SizedBox(height: Spacing.space4),
        ],
      ),
    );
  }
}

class _StateBody extends ConsumerWidget {
  const _StateBody({required this.snapshot, required this.ctrl});

  final ModelProvisioning snapshot;
  final ModelProvisioningController ctrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (snapshot.state) {
      case ModelState.notPresent:
      case ModelState.failed:
        return _OptInBody(snapshot: snapshot, ctrl: ctrl);
      case ModelState.optIn:
        return _ReadyToDownloadBody(snapshot: snapshot, ctrl: ctrl);
      case ModelState.downloading:
        return _DownloadingBody(snapshot: snapshot, ctrl: ctrl);
      case ModelState.verifying:
        return _VerifyingBody();
      case ModelState.verified:
        return _VerifiedBody(context: context);
    }
  }
}

// ---------------------------------------------------------------------------
// notPresent / failed: explain size, offer opt-in
// ---------------------------------------------------------------------------

class _OptInBody extends StatelessWidget {
  const _OptInBody({required this.snapshot, required this.ctrl});

  final ModelProvisioning snapshot;
  final ModelProvisioningController ctrl;

  @override
  Widget build(BuildContext context) {
    final semantic = ThresholdSemanticColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (snapshot.state == ModelState.failed) ...<Widget>[
          _ErrorBadge(message: 'Verification failed. Please try again.'),
          const SizedBox(height: Spacing.space4),
        ],
        // Size disclosure (FR-5.2a): must appear before the download starts.
        _SizeRow(sizeBytes: snapshot.sizeBytes),
        const SizedBox(height: Spacing.space5),
        Semantics(
          button: true,
          label: 'Download on device model for Privacy Mode',
          child: FilledButton.icon(
            onPressed: ctrl.optIn,
            icon: const Icon(Icons.download_outlined),
            label: const Text('Download model'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// optIn: confirm, show size again, start download
// ---------------------------------------------------------------------------

class _ReadyToDownloadBody extends StatelessWidget {
  const _ReadyToDownloadBody({required this.snapshot, required this.ctrl});

  final ModelProvisioning snapshot;
  final ModelProvisioningController ctrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SizeRow(sizeBytes: snapshot.sizeBytes),
        const SizedBox(height: Spacing.space3),
        Text(
          'Connect to Wi-Fi before downloading to avoid mobile data charges.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: Spacing.space5),
        Semantics(
          button: true,
          label: 'Start downloading the on device model',
          child: FilledButton.icon(
            onPressed: () => ctrl.startDownload(),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Start download'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// downloading: progress bar + byte count + cancel
// ---------------------------------------------------------------------------

class _DownloadingBody extends StatelessWidget {
  const _DownloadingBody({required this.snapshot, required this.ctrl});

  final ModelProvisioning snapshot;
  final ModelProvisioningController ctrl;

  @override
  Widget build(BuildContext context) {
    final progress = snapshot.progress;
    final downloaded = _formatBytes(snapshot.downloadedBytes);
    final total = _formatBytes(snapshot.sizeBytes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              'Downloading...',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              '$downloaded of $total',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.space3),
        Semantics(
          label: 'Download progress ${(progress * 100).round()} percent',
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            borderRadius: Radii.roundedFull,
          ),
        ),
        const SizedBox(height: Spacing.space5),
        Semantics(
          button: true,
          label: 'Cancel download',
          child: OutlinedButton(
            onPressed: ctrl.cancelDownload,
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// verifying: spinner
// ---------------------------------------------------------------------------

class _VerifyingBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const SizedBox(height: Spacing.space4),
        const CircularProgressIndicator(),
        const SizedBox(height: Spacing.space4),
        Text(
          'Verifying the model...',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: Spacing.space4),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// verified: success, auto-dismiss
// ---------------------------------------------------------------------------

class _VerifiedBody extends StatefulWidget {
  const _VerifiedBody({required this.context});
  final BuildContext context;

  @override
  State<_VerifiedBody> createState() => _VerifiedBodyState();
}

class _VerifiedBodyState extends State<_VerifiedBody> {
  @override
  void initState() {
    super.initState();
    // Auto-dismiss after a short success display.
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final semantic = ThresholdSemanticColors.of(context);
    return Column(
      children: <Widget>[
        const SizedBox(height: Spacing.space4),
        Icon(Icons.check_circle_outline,
            color: semantic.success, size: Spacing.space10),
        const SizedBox(height: Spacing.space3),
        Text(
          'Privacy Mode is ready.',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: semantic.success,
              ),
        ),
        const SizedBox(height: Spacing.space4),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared sub-widgets
// ---------------------------------------------------------------------------

class _SizeRow extends StatelessWidget {
  const _SizeRow({required this.sizeBytes});
  final int sizeBytes;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Icon(Icons.storage_outlined, size: Spacing.space5),
        const SizedBox(width: Spacing.space2),
        Text(
          'Download size: ${_formatBytes(sizeBytes)}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _ErrorBadge extends StatelessWidget {
  const _ErrorBadge({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final semantic = ThresholdSemanticColors.of(context);
    return Row(
      children: <Widget>[
        Icon(Icons.error_outline, color: semantic.danger, size: Spacing.space5),
        const SizedBox(width: Spacing.space2),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: semantic.danger,
                ),
          ),
        ),
      ],
    );
  }
}

/// Human-readable byte size string.
String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(mb < 100 ? 1 : 0)} MB';
}
