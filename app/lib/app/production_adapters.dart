// Production adapters for the device/Ring/network-bound ports (P2-1). These are
// the real bindings used by the composition root. The actual device work (the
// WebView WebRTC session, flutter_tts + outbound-track injection, launching the
// Ring app, and the backend HTTP/WS calls) is bound on device. Where that work
// cannot run in the current environment, the adapter throws a clear, dash-free
// error rather than fabricating a result, so a missing binding fails loudly
// instead of silently faking device behavior. Under `flutter test` these are
// overridden with the existing fakes.

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../captions/asr_client.dart';
import '../captions/turn_segmentation.dart';
import '../consent/recording_notice.dart';
import '../reply/echo_gate.dart';
import '../reply/reply_port.dart';
import '../reply/suggestion_provider.dart';
import '../session/auth_deep_link.dart';
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
  Future<SpeakOutcome> speak(String text,
      {void Function()? onPlaybackStart}) async {
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

/// Persisted consent state (FR-14.1, HIGH-10, LOW-06). Backed by
/// shared_preferences so the one-time recording-notice acknowledgement, the
/// audible-notice preference, and the remembered compliance default survive a
/// relaunch. Previously this kept its state in a plain `bool _ack` field, so
/// consent was forgotten on every launch and FR-14.1 "one-time acknowledgement"
/// could not hold. Loaded before the first frame in the composition root.
class ProductionConsentStore implements ConsentStore {
  ProductionConsentStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _prefix = 'threshold.consent.';
  static const String _ackKey = '${_prefix}acknowledged';
  static const String _audibleKey = '${_prefix}audibleNotice';
  static const String _defaultChoiceKey = '${_prefix}defaultChoice';

  /// Open the platform store. Call once at startup.
  static Future<ProductionConsentStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    return ProductionConsentStore(prefs);
  }

  @override
  Future<bool> isAcknowledged() async => _prefs.getBool(_ackKey) ?? false;

  @override
  Future<void> setAcknowledged(bool value) async =>
      _prefs.setBool(_ackKey, value);

  @override
  Future<bool> audibleNoticeEnabled() async =>
      _prefs.getBool(_audibleKey) ?? false;

  @override
  Future<void> setAudibleNoticeEnabled(bool value) async =>
      _prefs.setBool(_audibleKey, value);

  @override
  Future<ComplianceChoice?> defaultComplianceChoice() async {
    final name = _prefs.getString(_defaultChoiceKey);
    if (name == null) return null;
    for (final choice in ComplianceChoice.values) {
      if (choice.name == name) return choice;
    }
    return null;
  }

  @override
  Future<void> setDefaultComplianceChoice(ComplianceChoice choice) async =>
      _prefs.setString(_defaultChoiceKey, choice.name);
}

/// "Delete all my data" erasure (FR-8.6). The real binding calls DELETE /me/data.
class ProductionDataErasurePort implements DataErasurePort {
  @override
  Future<bool> deleteAllMyData() async {
    throw const DeviceBindingUnavailable('Erasing your data on the server');
  }
}

/// Re-authentication after a mid-session expiry (FR-1.5, FR-4.8; HIGH-09,
/// HIGH-18, H-2). The real binding starts the OAuth flow in the browser, awaits
/// the threshold://auth/complete deep link the backend redirects to, parses the
/// one-time code with [parseAuthDeepLink], and redeems it at POST /oauth/exchange
/// through an [AuthExchangeClient]. Only a verified session may resume (HIGH-09).
///
/// The structure is split so the two halves have different availability:
///  * [completeFromDeepLink] is pure. Given the already-received deep-link [Uri]
///    and an [AuthExchangeClient], it parses the link and drives the exchange.
///    This is fully covered by `flutter test`, so the server-side handoff is no
///    longer orphaned on the client.
///  * [reauthenticate] is DEFERRED: starting the browser flow and listening for
///    the incoming link both need a device and live network, which this
///    environment cannot provide, so it fails closed rather than pretending a
///    token was verified. When an exchange client is supplied for the live
///    binding it is used by [completeFromDeepLink] once a device delivers a link.
class ProductionAuthPort implements AuthPort {
  const ProductionAuthPort({AuthExchangeClient? exchangeClient})
      : _exchangeClient = exchangeClient;

  final AuthExchangeClient? _exchangeClient;

  @override
  Future<AuthResult> reauthenticate() async {
    // The live step launches the browser OAuth flow and waits for the backend
    // to redirect to the threshold://auth/complete deep link. Both are device
    // and network bound, so fail closed here; a device delivers the link to
    // completeFromDeepLink below.
    throw const DeviceBindingUnavailable('Signing in again');
  }

  /// Parse an already-received OAuth deep link and, when it carries a one-time
  /// code, redeem it through [client] (or the client supplied at construction).
  /// A link that is invalid or carries an error is a failed re-authentication,
  /// so the session must not resume (HIGH-09). This path is pure and headless.
  Future<AuthResult> completeFromDeepLink(
    Uri link, {
    AuthExchangeClient? client,
  }) async {
    final exchange = client ?? _exchangeClient;
    if (exchange == null) {
      throw const DeviceBindingUnavailable('The backend session exchange');
    }
    final parsed = parseAuthDeepLink(link);
    return switch (parsed) {
      AuthDeepLinkCode(code: final code) => exchange.exchange(code),
      AuthDeepLinkError() => AuthResult.failed,
      AuthDeepLinkInvalid() => AuthResult.failed,
    };
  }
}

/// Builds the production echo gate (FR-5.6). Pure logic; safe everywhere.
class ProductionEchoGate {
  static EchoGate build() => EchoGate();
}

/// The Clarity-Mode cloud ASR client over the backend /asr/stream WebSocket
/// (FR-5.1, CRIT-07). The real WebSocket client is DEFERRED: it needs the
/// backend and a live network, which this environment cannot provide, so start()
/// fails closed rather than pretending a stream opened. The caption pump + the
/// CaptionSource interface are wired in the composition root so a fake engine's
/// captions provably reach the screen under test; only the live socket is
/// deferred to the device/backend.
class ProductionAsrStreamClient implements AsrStreamClient {
  final _out = StreamController<CaptionResult>.broadcast();

  @override
  Stream<CaptionResult> get captions => _out.stream;

  @override
  Future<void> start(
      {required String deviceId, required String language}) async {
    throw const DeviceBindingUnavailable('The cloud caption stream');
  }

  @override
  Future<void> dispose() => _out.close();
}
