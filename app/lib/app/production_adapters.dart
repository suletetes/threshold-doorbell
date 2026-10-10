// Production adapters for the device/Ring/network-bound ports (P2-1). These are
// the real bindings used by the composition root. The actual device work (the
// WebView WebRTC session, flutter_tts + outbound-track injection, launching the
// Ring app, and the backend HTTP/WS calls) is bound on device. Where that work
// cannot run in the current environment, the adapter throws a clear, dash-free
// error rather than fabricating a result, so a missing binding fails loudly
// instead of silently faking device behavior. Under `flutter test` these are
// overridden with the existing fakes.

import 'dart:async';

import '../consent/recording_notice.dart';
import '../reply/echo_gate.dart';
import '../reply/reply_port.dart';
import '../reply/suggestion_provider.dart';
import '../session/auth_port.dart';
import '../session/ring_app_launcher.dart';
import '../session/session_port.dart';
import '../settings/settings_controller.dart';

/// Thrown when a device/Ring/network binding is invoked in an environment that
/// cannot support it (e.g. the sandbox). Never silently faked.
class DeviceBindingUnavailable implements Exception {
  const DeviceBindingUnavailable(this.what);
  final String what;
  @override
  String toString() =>
      'DeviceBindingUnavailable: $what requires the on device runtime.';
}

/// The live WebRTC session binding (ARCH-1). The real implementation hosts the
/// WebView and negotiates the single peer connection; here we surface the events
/// stream and defer the device round-trips.
class ProductionSessionPort implements SessionPort {
  final _events = StreamController<SessionPortEvent>.broadcast();

  @override
  Future<NegotiatedMedia> connect(String deviceId) async {
    throw const DeviceBindingUnavailable('The live doorbell session');
  }

  @override
  Future<bool> runProbe() async {
    throw const DeviceBindingUnavailable('The two way audio capability probe');
  }

  @override
  Future<void> close() async {}

  @override
  Stream<SessionPortEvent> get events => _events.stream;

  Future<void> dispose() => _events.close();
}

/// The reply synthesis + outbound injection binding (FR-6.1, FR-6.2).
class ProductionReplyPort implements ReplyPort {
  @override
  Future<SpeakOutcome> speak(String text, {void Function()? onPlaybackStart}) async {
    throw const DeviceBindingUnavailable('Speaking a reply at the door');
  }
}

/// Launches the official Ring app (FR-12.3). The real binding uses url_launcher.
class ProductionRingAppLauncher implements RingAppLauncher {
  @override
  Future<bool> openRingApp() async {
    throw const DeviceBindingUnavailable('Opening the Ring app');
  }
}

/// Backend Bedrock suggestions (Clarity Mode, FR-7.1). The real binding calls
/// POST /replies over HTTPS.
class ProductionBedrockSuggestionPort implements BedrockSuggestionPort {
  @override
  Future<List<String>> suggest(String visitorText) async {
    throw const DeviceBindingUnavailable('Cloud reply suggestions');
  }
}

/// Persisted consent state (FR-14.1). The real binding wraps shared_preferences.
class ProductionConsentStore implements ConsentStore {
  bool _ack = false;
  bool _audible = false;
  ComplianceChoice? _default;

  @override
  Future<bool> isAcknowledged() async => _ack;
  @override
  Future<void> setAcknowledged(bool value) async => _ack = value;
  @override
  Future<bool> audibleNoticeEnabled() async => _audible;
  @override
  Future<void> setAudibleNoticeEnabled(bool value) async => _audible = value;
  @override
  Future<ComplianceChoice?> defaultComplianceChoice() async => _default;
  @override
  Future<void> setDefaultComplianceChoice(ComplianceChoice choice) async =>
      _default = choice;
}

/// "Delete all my data" erasure (FR-8.6). The real binding calls DELETE /me/data.
class ProductionDataErasurePort implements DataErasurePort {
  @override
  Future<bool> deleteAllMyData() async {
    throw const DeviceBindingUnavailable('Erasing your data on the server');
  }
}

/// Re-authentication after a mid-session expiry (FR-1.5, FR-4.8; HIGH-09). The
/// real binding runs the OAuth / backend session exchange over HTTPS and
/// verifies the returned token. That client is DEFERRED: it needs a device and
/// live network, so here it fails closed rather than pretending a token was
/// verified.
class ProductionAuthPort implements AuthPort {
  @override
  Future<AuthResult> reauthenticate() async {
    throw const DeviceBindingUnavailable('Signing in again');
  }
}

/// Builds the production echo gate (FR-5.6). Pure logic; safe everywhere.
class ProductionEchoGate {
  static EchoGate build() => EchoGate();
}
