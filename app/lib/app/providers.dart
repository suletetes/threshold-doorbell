// Composition-root providers (Task 30 wiring, P2-1). This assembles the
// controllers and ports into a running product with Riverpod. Device/Ring-bound
// bindings (the WebView session, TTS+injection, launching the Ring app, and the
// backend network calls) sit behind their existing interfaces; the PRODUCTION
// adapters here defer the device work to the on-device runtime and are overridden
// by fakes under `flutter test` (see the ProviderScope overrides in the widget
// test). Nothing here fabricates device behavior: the production adapters either
// wrap a real integration point or throw a clear "device only" error if invoked
// in an environment that cannot support it.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../captions/model_provisioning.dart';
import '../consent/recording_notice.dart';
import '../consent/recording_notice_controller.dart';
import '../reply/reply_controller.dart';
import '../reply/reply_port.dart';
import '../reply/suggestion_provider.dart';
import '../session/auth_port.dart';
import '../session/ring_app_launcher.dart';
import '../session/session_controller.dart';
import '../session/session_port.dart';
import '../session/session_start_coordinator.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_store.dart';
import 'production_adapters.dart';

/// The on-device model download size disclosed before download (FR-5.2a). A
/// representative small Whisper model size; the real value comes from the model
/// manifest on device.
const int kModelSizeBytes = 75 * 1024 * 1024;

// --- Device/Ring-bound ports (overridden by fakes in tests) ---

final sessionPortProvider = Provider<SessionPort>((ref) {
  final port = ProductionSessionPort();
  ref.onDispose(port.dispose);
  return port;
});

final replyPortProvider = Provider<ReplyPort>((ref) => ProductionReplyPort());

final ringAppLauncherProvider =
    Provider<RingAppLauncher>((ref) => ProductionRingAppLauncher());

/// The app-to-backend re-authentication binding (FR-1.5, FR-4.8; HIGH-09). The
/// real backend session client is deferred; the production adapter fails closed.
final authPortProvider = Provider<AuthPort>((ref) => ProductionAuthPort());

final bedrockSuggestionPortProvider =
    Provider<BedrockSuggestionPort>((ref) => ProductionBedrockSuggestionPort());

/// The persisted consent store (FR-14.1, HIGH-10). In production main() loads a
/// shared_preferences-backed [ProductionConsentStore] before the first frame and
/// overrides this provider, so consent survives a relaunch. The default here is
/// an in-memory fake, used only under `flutter test` and never in a release
/// build (release always goes through bootstrapOverrides in main.dart).
final consentStoreProvider =
    Provider<ConsentStore>((ref) => FakeConsentStore());

/// The persisted settings store (HIGH-10). As with [consentStoreProvider],
/// production overrides this with a shared_preferences-backed store before the
/// first frame; the in-memory default is used only in tests.
final settingsStoreProvider =
    Provider<SettingsStore>((ref) => InMemorySettingsStore());

final dataErasurePortProvider =
    Provider<DataErasurePort>((ref) => ProductionDataErasurePort());

// --- Controllers / machines ---

/// The settings controller, seeded from the persisted store (HIGH-10). main()
/// loads the saved settings before the first frame and overrides this provider
/// with the hydrated controller; the fallback here builds an unpersisted
/// controller so widget tests that only override the store or supply their own
/// controller still work.
final settingsControllerProvider = ChangeNotifierProvider<SettingsController>((ref) {
  return SettingsController(
    erasure: ref.watch(dataErasurePortProvider),
    store: ref.watch(settingsStoreProvider),
  );
});

final sessionControllerProvider = ChangeNotifierProvider<SessionController>((ref) {
  return SessionController(port: ref.watch(sessionPortProvider));
});

final recordingNoticeControllerProvider =
    ChangeNotifierProvider<RecordingNoticeController>((ref) {
  return RecordingNoticeController(ref.watch(consentStoreProvider));
});

/// The on-device model provisioning machine (FR-5.2a). Its state drives whether
/// Privacy Mode can be selected.
final modelProvisioningProvider = Provider<ModelProvisioningMachine>((ref) {
  return ModelProvisioningMachine(modelSizeBytes: kModelSizeBytes);
});

/// The suggestion provider that routes Clarity -> Bedrock, Privacy -> on-device
/// (FR-7.1a).
final suggestionProvider = Provider<SuggestionProvider>((ref) {
  return SuggestionProvider(bedrock: ref.watch(bedrockSuggestionPortProvider));
});

/// The pre-session coordinator that consults model provisioning + the recording
/// notice fallback (FR-5.2a, FR-14.3a).
final sessionStartCoordinatorProvider = Provider<SessionStartCoordinator>((ref) {
  return SessionStartCoordinator(
    provisioning: ref.watch(modelProvisioningProvider),
    recordingNotice: ref.watch(recordingNoticeControllerProvider),
  );
});

/// The reply controller for the active session. Bound to the session's sticky
/// outbound-mode machine so the reply bar reflects the current capability.
///
/// This reads the session controller through `.notifier` rather than watching
/// the ChangeNotifierProvider directly (HIGH-03). Watching the provider re-ran
/// this builder on EVERY `notifyListeners()` (every caption, reconnect or
/// haptic tick), disposing and recreating the reply controller mid-send and
/// throwing "used after being disposed". `.notifier` gives a stable controller
/// reference without subscribing to its change stream, so a reply in flight
/// survives a caption or notification tick. The reply controller is rebuilt only
/// when the session identity changes, which is what rebinds it to a new
/// session's fresh outbound-mode machine (FR-6.4b).
final replyControllerProvider = ChangeNotifierProvider<ReplyController>((ref) {
  final session = ref.watch(sessionControllerProvider.notifier);
  final reply = ReplyController(
    port: ref.watch(replyPortProvider),
    outbound: session.outbound,
    echoGate: ProductionEchoGate.build(),
  );
  // Gate the caption pipeline on the reply's echo gate so our own reply audio
  // returning on the doorbell mic is never captioned as the visitor (FR-5.6,
  // HIGH-05). Cleared when this reply controller is disposed.
  session.shouldTranscribe = () => reply.shouldTranscribe;
  ref.onDispose(() {
    if (session.shouldTranscribe != null) session.shouldTranscribe = null;
  });
  return reply;
});
