// In-context permission prompt (Task 20, FR-13.2, FR-13.3, FR-13.4; AT-13).
// Shows the plain-language rationale immediately before the first request
// (FR-13.2). On denial it explains what is unavailable without blocking
// (FR-13.3); on permanent denial it shows a one-tap OS-settings deep link and
// does not re-prompt (FR-13.4). Every control carries a Semantics label (G4).

import 'package:flutter/material.dart';

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
            return _card(
              context,
              key: const ValueKey('permission-rationale'),
              message: rationaleFor(permission),
              actionLabel: 'Continue',
              actionKey: const ValueKey('permission-request'),
              onAction: () => controller.request(permission),
            );
          case PermissionUiState.deniedRetryable:
            return _card(
              context,
              key: const ValueKey('permission-denied'),
              message: unavailableExplanationFor(permission),
              actionLabel: 'Try again',
              actionKey: const ValueKey('permission-retry'),
              onAction: () => controller.request(permission),
            );
          case PermissionUiState.needsSettings:
            return _card(
              context,
              key: const ValueKey('permission-settings'),
              message: unavailableExplanationFor(permission),
              actionLabel: 'Open settings',
              actionKey: const ValueKey('permission-open-settings'),
              onAction: () => controller.openSettings(),
            );
        }
      },
    );
  }

  Widget _card(
    BuildContext context, {
    required Key key,
    required String message,
    required String actionLabel,
    required Key actionKey,
    required VoidCallback onAction,
  }) {
    return Card(
      key: key,
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              liveRegion: true,
              label: message,
              excludeSemantics: true,
              child: Text(message, style: const TextStyle(fontSize: 16, height: 1.3)),
            ),
            const SizedBox(height: 16),
            Semantics(
              button: true,
              label: actionLabel,
              excludeSemantics: true,
              child: FilledButton(
                key: actionKey,
                onPressed: onAction,
                child: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
