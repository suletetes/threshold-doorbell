// Threshold composition root (P2-1). A two-way captioned Ring doorbell for deaf
// and hard-of-hearing residents.
//
// This wires the product together: a Riverpod ProviderScope assembles the
// controllers (session, reply, settings, recording notice) and the device/Ring/
// network ports (behind their interfaces, with production adapters that defer
// device work). The home screen routes an answered door to the Conversation
// screen (two-way) or the Captions-Only screen (receive-only) per the sticky
// outbound mode, and to Settings. Device-bound work (WebView WebRTC, TTS +
// outbound injection, launching the Ring app, backend calls) lives behind the
// existing ports; nothing here fabricates device behavior.
//
// Persistence (HIGH-10): the settings and consent stores are loaded from
// shared_preferences BEFORE the first frame, so the first frame already
// reflects the resident's saved accessibility configuration and the one-time
// recording-notice acknowledgement (FR-14.1). The loaded stores and the
// hydrated settings controller are injected as provider overrides.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'alerts/doorbell_alert_service.dart';
import 'alerts/haptic_vocabulary.dart';
import 'app/mock_adapters.dart';
import 'app/production_adapters.dart';
import 'app/providers.dart';
import 'app/splash_screen.dart';
import 'captions/asr_client.dart';
import 'consent/recording_notice.dart';
import 'design/theme.dart';
import 'reply/reply_port.dart';
import 'reply/suggestion_provider.dart';
import 'settings/settings_controller.dart';
import 'settings/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load persisted settings and consent before the first frame (HIGH-10).
  final overrides = await bootstrapOverrides();
  runApp(ProviderScope(overrides: overrides, child: const ThresholdApp()));
}

/// Build the provider overrides that inject the persisted stores and the
/// hydrated settings controller (HIGH-10). Loaded before the first frame so the
/// resident's configuration and the FR-14.1 acknowledgement are present on the
/// first build rather than reset on every launch. Factored out of [main] so it
/// is testable and reusable.
Future<List<Override>> bootstrapOverrides() async {
  final consentStore = await ProductionConsentStore.open();
  final settingsStore = await SharedPreferencesSettingsStore.open();
  final settingsController = await SettingsController.load(
    erasure: ProductionDataErasurePort(),
    store: settingsStore,
  );
  // DEMO: mirror the person-at-door haptic setting into the doorbell alert
  // service, so the looping ring vibration honours the resident's toggle. Seed
  // the current value and keep it in sync on change.
  if (DemoConfig.enabled) {
    DoorbellAlertService.personAtDoorHapticEnabled =
        settingsController.settings.hapticEnabled[HapticEvent.personAtDoor] ??
            true;
    settingsController.onPersonAtDoorHapticChanged =
        (enabled) => DoorbellAlertService.personAtDoorHapticEnabled = enabled;
  }
  return <Override>[
    consentStoreProvider.overrideWith((ref) => consentStore as ConsentStore),
    settingsStoreProvider.overrideWith((ref) => settingsStore as SettingsStore),
    settingsControllerProvider.overrideWith((ref) => settingsController),
    // DEMO=true (two-phone WiFi doorbell demo): swap the device/Ring/cloud-bound
    // production stubs for the real backend-talking mock adapters. The app then
    // connects to BACKEND_URL for signaling, captions, and replies, and speaks
    // the chosen reply aloud on the resident phone. See lib/app/mock_adapters.dart.
    if (DemoConfig.enabled) ...<Override>[
      sessionPortProvider.overrideWith((ref) {
        final port = MockSessionPort();
        ref.onDispose(port.dispose);
        return port;
      }),
      captionSourceProvider.overrideWith((ref) {
        final client = MockAsrStreamClient();
        ref.onDispose(client.dispose);
        return client as CaptionSource;
      }),
      bedrockSuggestionPortProvider
          .overrideWith((ref) => BackendBedrockSuggestionPort() as BedrockSuggestionPort),
      replyPortProvider.overrideWith((ref) => MockReplyPort() as ReplyPort),
    ],
  ];
}

class ThresholdApp extends StatelessWidget {
  const ThresholdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Threshold',
      // Suppress the debug ribbon: this is a hackathon demo and an
      // accessibility product; the ribbon is noisy and obscures the top-right
      // corner that carries the settings action.
      debugShowCheckedModeBanner: false,
      // Accessibility is core to this product, not an afterthought:
      // large text, high contrast, full screen-reader support (WCAG 2.2 AA).
      // Both schemes are designed and contrast-tested in lib/design/; dark is
      // first-class because a doorbell is answered at night.
      theme: ThresholdTheme.light(),
      darkTheme: ThresholdTheme.dark(),
      themeMode: ThemeMode.system,
      home: const SplashScreen(),
    );
  }
}
