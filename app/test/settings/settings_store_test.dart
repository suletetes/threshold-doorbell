// Persistence tests (HIGH-10, LOW-06). Settings and consent MUST survive a
// relaunch: these prove a shared_preferences-backed store round-trips the
// resident's configuration across a simulated relaunch (a fresh store/controller
// built from the same backing values), and that the settings value type has real
// value equality so a round-trip through persistence compares equal.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:threshold/alerts/haptic_vocabulary.dart';
import 'package:threshold/app/production_adapters.dart';
import 'package:threshold/captions/language_selection.dart';
import 'package:threshold/consent/recording_notice.dart';
import 'package:threshold/settings/settings_controller.dart';
import 'package:threshold/settings/settings_state.dart';
import 'package:threshold/settings/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThresholdSettings value equality (LOW-06)', () {
    test('two settings with the same fields are equal and hash equally', () {
      final a = ThresholdSettings.defaults();
      final b = ThresholdSettings.defaults();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('a changed field makes them unequal', () {
      final a = ThresholdSettings.defaults();
      final b = a.copyWith(captionScale: 1.5);
      expect(a, isNot(equals(b)));
    });

    test('equality compares the haptic map by content, not identity', () {
      final a = ThresholdSettings.defaults();
      final b = a.copyWith(hapticEnabled: <HapticEvent, bool>{
        HapticEvent.personAtDoor: true,
        HapticEvent.motion: true,
        HapticEvent.conversationStarted: true,
      });
      expect(a, equals(b));
    });

    test('the haptic map cannot be mutated in place (truly immutable)', () {
      final s = ThresholdSettings.defaults();
      expect(
        () => s.hapticEnabled[HapticEvent.motion] = false,
        throwsUnsupportedError,
      );
    });
  });

  group('SharedPreferencesSettingsStore (HIGH-10)', () {
    test('settings survive a simulated relaunch', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = await SharedPreferencesSettingsStore.open();

      // Nothing saved yet: load() is null so the app uses defaults.
      expect(await store.load(), isNull);

      final customized = ThresholdSettings.defaults().copyWith(
        captionScale: 1.75,
        pendingMode: CaptionMode.privacy,
        strobeEnabled: true,
        language: 'fr-FR',
        audibleNoticeEnabled: true,
        captionForeground: const Color(0xFFFFFF00),
        captionBackground: const Color(0xFF101010),
        hapticEnabled: <HapticEvent, bool>{
          HapticEvent.personAtDoor: true,
          HapticEvent.motion: false,
          HapticEvent.conversationStarted: true,
        },
      );
      await store.save(customized);

      // Simulate a relaunch: a brand new store instance reading the SAME backing
      // values. The persisted values must come back, not the defaults.
      final relaunched = await SharedPreferencesSettingsStore.open();
      final loaded = await relaunched.load();
      expect(loaded, isNotNull);
      expect(loaded, equals(customized));
      expect(loaded!.captionScale, 1.75);
      expect(loaded.pendingMode, CaptionMode.privacy);
      expect(loaded.strobeEnabled, isTrue);
      expect(loaded.language, 'fr-FR');
      expect(loaded.hapticEnabled[HapticEvent.motion], isFalse);
    });

    test('clear() removes persisted settings', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = await SharedPreferencesSettingsStore.open();
      await store.save(ThresholdSettings.defaults().copyWith(captionScale: 2.0));
      expect(await store.load(), isNotNull);
      await store.clear();
      expect(await store.load(), isNull);
    });
  });

  group('SettingsController persistence (HIGH-10)', () {
    test('a controller change persists and reloads after a relaunch', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = await SharedPreferencesSettingsStore.open();

      final controller = await SettingsController.load(
        erasure: FakeDataErasurePort(),
        store: store,
      );
      // Default on first run.
      expect(controller.settings.captionScale, 1.0);

      controller.setCaptionScale(1.5);
      controller.setStrobeEnabled(true);
      // Let the fire-and-forget persistence complete.
      await Future<void>.delayed(Duration.zero);

      // Relaunch: a fresh controller from the same backing store must hydrate
      // the saved values, not the defaults.
      final reloaded = await SettingsController.load(
        erasure: FakeDataErasurePort(),
        store: store,
      );
      expect(reloaded.settings.captionScale, 1.5);
      expect(reloaded.settings.strobeEnabled, isTrue);
    });

    test('a successful erasure clears persisted settings too', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = await SharedPreferencesSettingsStore.open();
      final controller = await SettingsController.load(
        erasure: FakeDataErasurePort(succeeds: true),
        store: store,
      );
      controller.setCaptionScale(2.0);
      await Future<void>.delayed(Duration.zero);

      await controller.deleteAllMyData(confirmed: true);
      await Future<void>.delayed(Duration.zero);

      // Relaunch after erasure: the store is cleared, so defaults load.
      final reloaded = await SettingsController.load(
        erasure: FakeDataErasurePort(),
        store: store,
      );
      expect(reloaded.settings.captionScale, 1.0);
    });
  });

  group('ProductionConsentStore (HIGH-10, CRIT-06)', () {
    test('acknowledgement survives a simulated relaunch (FR-14.1)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = await ProductionConsentStore.open();
      expect(await store.isAcknowledged(), isFalse);

      await store.setAcknowledged(true);
      await store.setAudibleNoticeEnabled(true);
      await store.setDefaultComplianceChoice(ComplianceChoice.disableTranscription);

      // Relaunch: a new store over the same backing values.
      final relaunched = await ProductionConsentStore.open();
      expect(await relaunched.isAcknowledged(), isTrue);
      expect(await relaunched.audibleNoticeEnabled(), isTrue);
      expect(
        await relaunched.defaultComplianceChoice(),
        ComplianceChoice.disableTranscription,
      );
    });

    test('a fresh install starts unacknowledged', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = await ProductionConsentStore.open();
      expect(await store.isAcknowledged(), isFalse);
      expect(await store.defaultComplianceChoice(), isNull);
    });
  });
}
