import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/permissions/permission_controller.dart';
import 'package:threshold/permissions/permission_port.dart';
import 'package:threshold/permissions/permission_prompt.dart';

Widget _wrap(PermissionController c, AppPermission p) => MaterialApp(
      home: Scaffold(body: PermissionPrompt(controller: c, permission: p)),
    );

void main() {
  group('PermissionPrompt widget (Task 20, FR-13.2..13.4; AT-13)', () {
    testWidgets('shows the in-context rationale before requesting (FR-13.2)', (tester) async {
      final c = PermissionController(FakePermissionPort());
      await tester.pumpWidget(_wrap(c, AppPermission.microphone));
      await tester.pump();
      expect(find.byKey(const ValueKey('permission-rationale')), findsOneWidget);
      expect(find.textContaining('microphone'), findsOneWidget);
    });

    testWidgets('tapping Continue requests the permission', (tester) async {
      final port = FakePermissionPort(
        requestResults: <AppPermission, PermissionStatus>{
          AppPermission.microphone: PermissionStatus.granted,
        },
      );
      final c = PermissionController(port);
      await tester.pumpWidget(_wrap(c, AppPermission.microphone));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('permission-request')));
      await tester.pumpAndSettle();
      expect(port.requestedPermissions, <AppPermission>[AppPermission.microphone]);
      // Granted: the prompt disappears.
      expect(find.byKey(const ValueKey('permission-rationale')), findsNothing);
    });

    testWidgets('permanently denied shows the settings deep link, not a re-prompt (FR-13.4)', (tester) async {
      final port = FakePermissionPort(
        initial: <AppPermission, PermissionStatus>{
          AppPermission.notifications: PermissionStatus.permanentlyDenied,
        },
      );
      final c = PermissionController(port);
      await c.refresh(AppPermission.notifications);
      await tester.pumpWidget(_wrap(c, AppPermission.notifications));
      await tester.pump();
      expect(find.byKey(const ValueKey('permission-settings')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('permission-open-settings')));
      await tester.pump();
      expect(port.openSettingsCalls, 1);
      expect(port.requestedPermissions, isEmpty); // never re-prompted
    });

    testWidgets('denied shows a non-blocking explanation with retry (FR-13.3)', (tester) async {
      final port = FakePermissionPort(
        initial: <AppPermission, PermissionStatus>{
          AppPermission.microphone: PermissionStatus.denied,
        },
      );
      final c = PermissionController(port);
      await c.refresh(AppPermission.microphone);
      await tester.pumpWidget(_wrap(c, AppPermission.microphone));
      await tester.pump();
      expect(find.byKey(const ValueKey('permission-denied')), findsOneWidget);
      expect(find.byKey(const ValueKey('permission-retry')), findsOneWidget);
    });

    testWidgets('controls carry Semantics labels (G4)', (tester) async {
      final handle = tester.ensureSemantics();
      final c = PermissionController(FakePermissionPort());
      await tester.pumpWidget(_wrap(c, AppPermission.microphone));
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp('Continue')), findsOneWidget);
      handle.dispose();
    });
  });
}
