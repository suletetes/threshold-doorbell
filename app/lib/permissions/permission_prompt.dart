// In-context permission prompt (Task 20, FR-13.2, FR-13.3, FR-13.4; AT-13).
// Shows the plain-language rationale immediately before the first request
// (FR-13.2). On denial it explains what is unavailable without blocking
// (FR-13.3); on permanent denial it shows a one-tap OS-settings deep link and
// does not re-prompt (FR-13.4). Every control carries a Semantics label (G4).
//
// --- Presentation (UI/UX audit section 3.6 and section 5) -------------------
//
// The permission-denied explanation was the fourth of the four ad hoc "status
// message" treatments the audit found: a bare Card with a raw fontSize of 16 and
// a raw height of 1.3, with no icon distinguishing "we are about to ask you for
// something" from "this is now unavailable". It is now the shared StatusBanner,
// and the variant carries that distinction:
//
//   needsRationale  -> info.    We are about to ask. Nothing is wrong.
//   deniedRetryable -> warning. Something is unavailable but you can still fix it.
//   needsSettings   -> warning. Same, but the fix is in the OS, not here.
//
// Denial is deliberately NOT `danger`. FR-13.3 requires the explanation to be
// non-blocking, and a red banner reads as a blocked state.

import 'package:flutter/material.dart';

import '../design/components/components.dart';
import '../design/tokens.dart';
import 'permission_controller.dart';
import 'permission_port.dart';

class PermissionPrompt extends StatelessWidget {
  const PermissionPrompt({
    super.key,
    required this.controller,
    required this.permission,
  });

  final PermissionController controller;
  final AppPermission permission;

  /// The banner variant for a permission UI state. Exposed so the widget test
  /// asserts the mapping rather than a color.
  static StatusVariant variantFor(PermissionUiState state) {
    switch (state) {
      case PermissionUiState.granted:
      case PermissionUiState.needsRationale:
        return StatusVariant.info;
      case PermissionUiState.deniedRetryable:
      case PermissionUiState.needsSettings:
        // Non-blocking (FR-13.3): unavailable, not broken.
        return StatusVariant.warning;
    }
  }

  /// The icon for a permission UI state.
  static IconData iconFor(PermissionUiState state) {
    switch (state) {
      case PermissionUiState.granted:
      case PermissionUiState.needsRationale:
        return Icons.help_outline;
      case PermissionUiState.deniedRetryable:
        return Icons.block_outlined;
      case PermissionUiState.needsSettings:
        return Icons.settings_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final uiState = controller.uiStateOf(permission);
        switch (uiState) {
          case PermissionUiState.granted:
            return const SizedBox.shrink();
          case PermissionUiState.needsRationale:
            return _banner(
              uiState: uiState,
              cardKey: const ValueKey('permission-rationale'),
              message: rationaleFor(permission),
              actionLabel: 'Continue',
              actionIcon: Icons.arrow_forward_rounded,
              actionKey: const ValueKey('permission-request'),
              onAction: () => controller.request(permission),
            );
          case PermissionUiState.deniedRetryable:
            return _banner(
              uiState: uiState,
              cardKey: const ValueKey('permission-denied'),
              message: unavailableExplanationFor(permission),
              actionLabel: 'Try again',
              actionIcon: Icons.refresh_rounded,
              actionKey: const ValueKey('permission-retry'),
              onAction: () => controller.request(permission),
            );
          case PermissionUiState.needsSettings:
            return _banner(
              uiState: uiState,
              cardKey: const ValueKey('permission-settings'),
              message: unavailableExplanationFor(permission),
              actionLabel: 'Open settings',
              actionIcon: Icons.open_in_new,
              actionKey: const ValueKey('permission-open-settings'),
              onAction: () => controller.openSettings(),
            );
        }
      },
    );
  }

  Widget _banner({
    required PermissionUiState uiState,
    required Key cardKey,
    required String message,
    required String actionLabel,
    required IconData actionIcon,
    required Key actionKey,
    required VoidCallback onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.space4),
      child: StatusBanner(
        key: cardKey,
        variant: variantFor(uiState),
        icon: iconFor(uiState),
        message: message,
        action: StatusBannerAction(
          label: actionLabel,
          icon: actionIcon,
          buttonKey: actionKey,
          onPressed: onAction,
        ),
      ),
    );
  }
}
