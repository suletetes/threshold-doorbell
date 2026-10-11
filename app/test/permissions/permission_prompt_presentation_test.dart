// Permission prompt presentation (UI/UX audit section 3.6: the permission-denied
// explanation was the fourth ad hoc treatment of the same status message idea; and
// section 5: "adopt the shared components so the consent and permission surfaces
// match the rest of the app").
//
// The variant mapping is the interesting part. FR-13.3 requires the denial
// explanation to be NON-BLOCKING, so denial must not read as a red failure.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/design/components/components.dart';
import 'package:threshold/design/theme.dart';
import 'package:threshold/design/tokens.dart';
import 'package:threshold/permissions/permission_controller.dart';
import 'package:threshold/permissions/permission_port.dart';
import 'package:threshold/permissions/permission_prompt.dart';

Widget _host(PermissionController c, AppPermission p) => MaterialApp(
      theme: ThresholdTheme.light(),
      home: Scaffold(body: PermissionPrompt(controller: c, permission: p)),
    );

Future<PermissionController> _inState(
  AppPermission permission,
  PermissionStatus status,
) async {
  final port = FakePermissionPort(
    initial: <AppPermission, PermissionStatus>{permission: status},
  );
  final c = PermissionController(port);
  await c.refresh(permission);
  return c;
}

void main() {
  group('The prompt is the shared StatusBanner (audit section 3.6)', () {
    testWidgets('the rationale renders as a banner with an icon',
        (tester) async {
      final c = PermissionController(FakePermissionPort());
      await tester.pumpWidget(_host(c, AppPermission.microphone));
      await tester.pump();
      expect(find.byType(StatusBanner), findsOneWidget);
      expect(
          find.byKey(const ValueKey('permission-rationale')), findsOneWidget);
      expect(
        find.byIcon(PermissionPrompt.iconFor(PermissionUiState.needsRationale)),
        findsOneWidget,
      );
      expect(find.textContaining('microphone'), findsOneWidget);
    });

    testWidgets('the denied explanation renders as a banner with its own icon',
        (tester) async {
      final c =
          await _inState(AppPermission.microphone, PermissionStatus.denied);
      await tester.pumpWidget(_host(c, AppPermission.microphone));
      await tester.pump();
      expect(find.byKey(const ValueKey('permission-denied')), findsOneWidget);
      expect(
        find.byIcon(
            PermissionPrompt.iconFor(PermissionUiState.deniedRetryable)),
        findsOneWidget,
      );
    });

    testWidgets(
        'the settings deep link renders as a banner with a settings icon',
        (tester) async {
      final c = await _inState(
        AppPermission.notifications,
        PermissionStatus.permanentlyDenied,
      );
      await tester.pumpWidget(_host(c, AppPermission.notifications));
      await tester.pump();
      expect(find.byKey(const ValueKey('permission-settings')), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsWidgets);
    });

    testWidgets('each UI state gets a distinct icon', (tester) async {
      final icons = <PermissionUiState>[
        PermissionUiState.needsRationale,
        PermissionUiState.deniedRetryable,
        PermissionUiState.needsSettings,
      ].map(PermissionPrompt.iconFor).toSet();
      expect(icons.length, 3);
    });
  });

  group('Denial is non-blocking, not a failure (FR-13.3)', () {
    testWidgets('asking is info; denial is warning, never danger',
        (tester) async {
      expect(
        PermissionPrompt.variantFor(PermissionUiState.needsRationale),
        StatusVariant.info,
      );
      for (final state in <PermissionUiState>[
        PermissionUiState.deniedRetryable,
        PermissionUiState.needsSettings,
      ]) {
        expect(PermissionPrompt.variantFor(state), StatusVariant.warning);
        expect(
          PermissionPrompt.variantFor(state),
          isNot(StatusVariant.danger),
          reason: 'a red banner reads as blocked, which FR-13.3 forbids',
        );
      }
    });

    testWidgets('the rendered banner uses the mapped variant', (tester) async {
      final c =
          await _inState(AppPermission.microphone, PermissionStatus.denied);
      await tester.pumpWidget(_host(c, AppPermission.microphone));
      await tester.pump();
      final banner = tester.widget<StatusBanner>(
        find.byKey(const ValueKey('permission-denied')),
      );
      expect(banner.variant, StatusVariant.warning);
    });
  });

  group('Actions keep their weight, keys, and targets', () {
    testWidgets('each action is a real button with an icon at 48dp',
        (tester) async {
      final cases = <ValueKey<String>, PermissionController>{
        const ValueKey('permission-request'):
            PermissionController(FakePermissionPort()),
        const ValueKey('permission-retry'):
            await _inState(AppPermission.microphone, PermissionStatus.denied),
        const ValueKey('permission-open-settings'): await _inState(
            AppPermission.microphone, PermissionStatus.permanentlyDenied),
      };
      for (final entry in cases.entries) {
        await tester.pumpWidget(_host(entry.value, AppPermission.microphone));
        await tester.pump();
        expect(find.byKey(entry.key), findsOneWidget,
            reason: '${entry.key} missing');
        expect(
          tester.getSize(find.byKey(entry.key)).height,
          greaterThanOrEqualTo(TouchTarget.minimum),
        );
        expect(
            find.byWidgetPredicate((w) => w is FilledButton), findsOneWidget);
      }
    });

    testWidgets('granted renders nothing at all', (tester) async {
      final c =
          await _inState(AppPermission.microphone, PermissionStatus.granted);
      await tester.pumpWidget(_host(c, AppPermission.microphone));
      await tester.pump();
      expect(find.byType(StatusBanner), findsNothing);
    });

    testWidgets('semantics survive the refactor (G4)', (tester) async {
      final handle = tester.ensureSemantics();
      final c = PermissionController(FakePermissionPort());
      await tester.pumpWidget(_host(c, AppPermission.microphone));
      await tester.pump();
      expect(find.bySemanticsLabel('Continue'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('microphone')), findsOneWidget);
      handle.dispose();
    });
  });
}
