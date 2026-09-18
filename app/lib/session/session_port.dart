// Live-session device binding port (Task 12, FR-4.1..FR-4.8; AT-3).
//
// ARCH-1: the live session runs entirely inside an in-app WebView that owns the
// single RTCPeerConnection (audio sendrecv, video recvonly). The WebView, the
// webview_flutter widget, the WHEP offer/answer relay over /signaling, and the
// real getStats() capability probe are all device/Ring bound and NOT available
// in this sandbox (no emulator, no live Ring). They are therefore placed behind
// this SessionPort interface. The live binding is created only in the
// composition root; the SessionController and the Conversation screen depend on
// this interface, and a FakeSessionPort drives every lifecycle state under
// `flutter test`.

import 'dart:async';

/// The negotiated media shape of the single peer connection (ARCH-1, AT-3).
/// The live binding fills this from the SDP answer; the fake supplies a
/// deterministic sendrecv-audio / recvonly-video shape so AT-3 is asserted
/// without a device.
class NegotiatedMedia {
  const NegotiatedMedia({
    required this.audioDirection,
    required this.videoDirection,
    required this.peerConnectionCount,
  });

  /// Should be 'sendrecv' for audio (FR-4.1, AT-3).
  final String audioDirection;

  /// Should be 'recvonly' for video (FR-4.1, AT-3).
  final String videoDirection;

  /// Exactly one peer connection exists (ARCH-1, AT-3).
  final int peerConnectionCount;

  bool get isArch1Compliant =>
      audioDirection == 'sendrecv' &&
      videoDirection == 'recvonly' &&
      peerConnectionCount == 1;
}

/// A signaling/connection event surfaced by the port.
enum SessionPortEvent {
  /// The peer connection reached `connected` (design §5.1 precondition).
  connected,

  /// Connection setup failed for this attempt (FR-4.4).
  connectFailed,

  /// The live connection dropped (net drop from LIVE, design §5.2).
  dropped,

  /// A reconnect attempt succeeded, connection is live again.
  reconnected,

  /// A reconnect attempt failed.
  reconnectFailed,

  /// The backend/app session credential expired mid-use (FR-4.8).
  authExpired,

  /// The signaling broker rejected a second concurrent session with 4409
  /// (FR-4.6/4.7; design §4). The app must not open a second peer connection.
  sessionAlreadyActive,
}

/// The device binding for one live session. All methods are async so the live
/// WebView binding can await signaling round-trips; the fake resolves instantly.
abstract class SessionPort {
  /// Open the single peer connection for [deviceId] and negotiate media
  /// (ARCH-1). Completes when the connection reaches `connected` or throws on a
  /// setup failure (the controller applies the retry budget of FR-4.4).
  Future<NegotiatedMedia> connect(String deviceId);

  /// Run the near-silent capability probe (design §5.1) and return whether
  /// outbound audio is available (FR-6.4a). Sticky handling lives in the
  /// OutboundModeMachine; this only reports the raw probe result.
  Future<bool> runProbe();

  /// Close the peer connection and release the Ring session URL (FR-4.3).
  Future<void> close();

  /// A stream of connection/signaling events the controller reacts to.
  Stream<SessionPortEvent> get events;
}

/// Deterministic fake that drives every lifecycle state without a device. Tests
/// script the connect outcome, the probe result, and push events to exercise
/// reconnect, background, auth recovery, and concurrency.
class FakeSessionPort implements SessionPort {
  FakeSessionPort({
    this.probeSucceeds = true,
    List<ConnectPlan>? connectPlan,
    NegotiatedMedia? media,
  })  : _connectPlan = List<ConnectPlan>.from(
          connectPlan ?? const <ConnectPlan>[ConnectPlan.succeed],
        ),
        _media = media ??
            const NegotiatedMedia(
              audioDirection: 'sendrecv',
              videoDirection: 'recvonly',
              peerConnectionCount: 1,
            );

  /// Whether the probe reports outbound available (FR-6.4a).
  bool probeSucceeds;

  final List<ConnectPlan> _connectPlan;
  final NegotiatedMedia _media;
  final _events = StreamController<SessionPortEvent>.broadcast();

  int connectCalls = 0;
  int probeCalls = 0;
  int closeCalls = 0;
  bool get isClosed => closeCalls > 0;

  @override
  Future<NegotiatedMedia> connect(String deviceId) async {
    connectCalls++;
    final plan = _connectPlan.isEmpty
        ? ConnectPlan.succeed
        : _connectPlan.removeAt(0);
    if (plan == ConnectPlan.fail) {
      throw const SessionConnectException('connect failed');
    }
    return _media;
  }

  @override
  Future<bool> runProbe() async {
    probeCalls++;
    return probeSucceeds;
  }

  @override
  Future<void> close() async {
    closeCalls++;
  }

  @override
  Stream<SessionPortEvent> get events => _events.stream;

  /// Push an event to the controller (test helper).
  void emit(SessionPortEvent event) => _events.add(event);

  Future<void> dispose() => _events.close();
}

/// Scripted outcome of a single connect attempt for the fake.
enum ConnectPlan { succeed, fail }

/// Thrown by [SessionPort.connect] when a setup attempt fails (FR-4.4).
class SessionConnectException implements Exception {
  const SessionConnectException(this.message);
  final String message;
  @override
  String toString() => 'SessionConnectException: $message';
}
