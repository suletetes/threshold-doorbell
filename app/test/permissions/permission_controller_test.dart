import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/permissions/permission_controller.dart';
import 'package:threshold/permissions/permission_port.dart';

void main() {
  group('AppPermission enum (Task 20, FR-13.1; AT-13)', () {
    test('camera is never a requestable permission (FR-13.1)', () {
      // The enum has exactly notifications and microphone; no camera exists, so
      // the app cannot request it by construction.
      expect(AppPermission.values, <AppPermission>[
        AppPermission.notifications,
        AppPermission.microphone,
      ]);
    });
  });

  group('PermissionController flow (Task 20, FR-13.2..13.5; AT-13)', () {
    test('starts by needing the in-context rationale (FR-13.2)', () {
      final c = PermissionController(FakePermissionPort());
      expect(c.uiStateOf(AppPermission.microphone), PermissionUiState.needsRationale);
    });

    test('granting a permission makes the feature available', () async {
      final port = FakePermissionPort(
        requestResults: <AppPermission, PermissionStatus>{
          AppPermission.microphone: PermissionStatus.granted,
        },
      );
      final c = PermissionController(port);
      final state = await c.request(AppPermission.microphone);
      expect(state, PermissionUiState.granted);
      expect(port.requestedPermissions, <AppPermission>[AppPermission.microphone]);
    });

    test('denied is retryable and does not block (FR-13.3)', () async {
      final port = FakePermissionPort(
        requestResults: <AppPermission, PermissionStatus>{
          AppPermission.microphone: PermissionStatus.denied,
        },
      );
      final c = PermissionController(port);
      final state = await c.request(AppPermission.microphone);
      expect(state, PermissionUiState.deniedRetryable);
    });

    test('permanently denied routes to settings and does NOT re-prompt (FR-13.4)', () async {
      final port = FakePermissionPort(
        initial: <AppPermission, PermissionStatus>{
          AppPermission.microphone: PermissionStatus.permanentlyDenied,
        },
      );
      final c = PermissionController(port);
      await c.refresh(AppPermission.microphone);
      expect(c.uiStateOf(AppPermission.microphone), PermissionUiState.needsSettings);
      // A request while permanently denied must not re-prompt the OS.
      final state = await c.request(AppPermission.microphone);
      expect(state, PermissionUiState.needsSettings);
      expect(port.requestedPermissions, isEmpty); // never re-prompted
    });

    test('open settings deep link is used for permanent denial (FR-13.4)', () async {
      final port = FakePermissionPort();
      final c = PermissionController(port);
      final opened = await c.openSettings();
      expect(opened, isTrue);
      expect(port.openSettingsCalls, 1);
    });

    test('notification denial activates the poll fallback (FR-13.5)', () async {
      final port = FakePermissionPort(
        requestResults: <AppPermission, PermissionStatus>{
          AppPermission.notifications: PermissionStatus.denied,
        },
      );
      final c = PermissionController(port);
      expect(c.pollFallbackActive, isFalse);
      await c.request(AppPermission.notifications);
      expect(c.pollFallbackActive, isTrue);
    });

    test('notification permanent denial also activates the poll fallback (FR-13.5)', () async {
      final port = FakePermissionPort(
        initial: <AppPermission, PermissionStatus>{
          AppPermission.notifications: PermissionStatus.permanentlyDenied,
        },
      );
      final c = PermissionController(port);
      await c.refresh(AppPermission.notifications);
      expect(c.pollFallbackActive, isTrue);
    });

    test('granted notifications keep push active (no poll fallback)', () async {
      final port = FakePermissionPort(
        requestResults: <AppPermission, PermissionStatus>{
          AppPermission.notifications: PermissionStatus.granted,
        },
      );
      final c = PermissionController(port);
      await c.request(AppPermission.notifications);
      expect(c.pollFallbackActive, isFalse);
    });

    test('rationale and explanation strings are dash-free (NFR-10)', () {
      for (final p in AppPermission.values) {
        expect(rationaleFor(p).contains('\u2014'), isFalse);
        expect(rationaleFor(p).contains('\u2013'), isFalse);
        expect(unavailableExplanationFor(p).contains('\u2014'), isFalse);
        expect(unavailableExplanationFor(p).contains('\u2013'), isFalse);
      }
    });
  });
}
