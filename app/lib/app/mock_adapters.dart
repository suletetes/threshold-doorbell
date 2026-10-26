// Demo mock adapters for the two-phone WiFi doorbell demo (DEMO=true).
//
// These are the REAL resident-side bindings that talk to the Threshold backend,
// replacing the ProductionXxx stubs that throw DeviceBindingUnavailable. They
// are audio-only (no WebView video panel): the full accessibility value —
// live captions and a spoken reply — works end to end against the backend in
// demo/local mode, driven by the visitor side at app/spike/phone_doorbell.html.
//
// Wiring: main.dart reads --dart-define=DEMO and --dart-define=BACKEND_URL and,
// when DEMO=true, overrides the production providers with these adapters.
//
// Backend protocol (see backend/src/routes/signaling.ts and asr.ts):
//   /signaling  client -> {type:'offer', deviceId, sdp}
//               server -> {type:'answer', sdpAnswer, sessionUrl}
//   /asr/stream server -> caption JSON frames {transcript, isFinal, confidence}
//   POST /replies  {visitorText, language, mode:'clarity'} -> {suggestions:[...]}

import 'dart:async';
import 'dart:convert';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../captions/asr_client.dart';
import '../captions/turn_segmentation.dart';
import '../reply/reply_port.dart';
import '../reply/suggestion_provider.dart';
import '../session/session_port.dart';

/// A millisecond clock, injectable for deterministic tests.
typedef NowMs = int Function();

/// Demo configuration read from --dart-define at build time.
class DemoConfig {
  /// True when the app is built with --dart-define=DEMO=true.
  static const bool enabled = bool.fromEnvironment('DEMO', defaultValue: false);

  /// The backend base URL, e.g. http://192.168.1.42:8080 (laptop LAN IP).
  /// Defaults to localhost for an emulator on the same machine.
  static const String backendUrl =
      String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8080');

  /// The device id used for the demo doorbell (matches phone_doorbell.html).
  static const String deviceId =
      String.fromEnvironment('DEVICE_ID', defaultValue: 'mock-doorbell-001');

  /// A demo session token. In local/demo mode the backend accepts this as the
  /// session cookie. Override with a real token for a deployed backend.
  static const String sessionToken =
      String.fromEnvironment('SESSION_TOKEN', defaultValue: 'demo-session-token');

  /// The ws:// or wss:// base derived from [backendUrl].
  static String get wsBase =>
      backendUrl.replaceFirst(RegExp(r'^http'), 'ws');
}

// ---------------------------------------------------------------------------
// MockSessionPort — opens the /signaling WebSocket and negotiates the session.
// ---------------------------------------------------------------------------

/// Connects to the backend /signaling broker over WebSocket, performs the
/// offer/answer exchange, and reports the ARCH-1 media shape. Audio-only: the
/// SDP offer is a minimal placeholder because in demo mode the backend uses
/// FixtureRingSignaling, which returns a canned sendrecv-audio / recvonly-video
/// answer regardless of the offer body.
class MockSessionPort implements SessionPort {
  MockSessionPort({String? backendWsBase, String? deviceId})
      : _wsBase = backendWsBase ?? DemoConfig.wsBase,
        _deviceId = deviceId ?? DemoConfig.deviceId;

  final String _wsBase;
  final String _deviceId;

  WebSocketChannel? _channel;
  final _events = StreamController<SessionPortEvent>.broadcast();

  @override
  Stream<SessionPortEvent> get events => _events.stream;

  @override
  Future<NegotiatedMedia> connect(String deviceId) async {
    final uri = Uri.parse('$_wsBase/signaling');
    // Pass the session token via the Sec-WebSocket-Protocol subprotocol (the
    // browser-safe way to pass a credential on a WS that the backend accepts;
    // see ws-auth.ts). This avoids putting the token in the URL query string
    // (which ends up in ALB access logs).
    final protocols = <String>[
      'threshold.session.${DemoConfig.sessionToken}',
    ];
    final channel = WebSocketChannel.connect(uri, protocols: protocols);
    _channel = channel;

    final answer = Completer<NegotiatedMedia>();

    channel.stream.listen(
      (dynamic raw) {
        final msg = _tryDecode(raw);
        if (msg == null) return;
        final type = msg['type'];
        if (type == 'answer') {
          if (!answer.isCompleted) {
            // FixtureRingSignaling always negotiates sendrecv audio / recvonly
            // video with exactly one peer connection (AT-3 / ARCH-1).
            answer.complete(
              const NegotiatedMedia(
                audioDirection: 'sendrecv',
                videoDirection: 'recvonly',
                peerConnectionCount: 1,
              ),
            );
            _events.add(SessionPortEvent.connected);
          }
        } else if (type == 'error') {
          final code = (msg['code'] ?? '').toString();
          if (!answer.isCompleted) {
            answer.completeError(SessionConnectException(code.isEmpty ? 'error' : code));
          }
          if (code == 'session_already_active') {
            _events.add(SessionPortEvent.sessionAlreadyActive);
          } else {
            _events.add(SessionPortEvent.connectFailed);
          }
        }
      },
      onError: (Object e) {
        if (!answer.isCompleted) {
          answer.completeError(SessionConnectException(e.toString()));
        }
        _events.add(SessionPortEvent.dropped);
      },
      onDone: () {
        if (!answer.isCompleted) {
          answer.completeError(const SessionConnectException('closed before answer'));
        }
      },
      cancelOnError: false,
    );

    // Send the offer. The SDP body is a placeholder; the fixture broker does not
    // parse it beyond requiring a non-empty string.
    channel.sink.add(jsonEncode(<String, String>{
      'type': 'offer',
      'deviceId': deviceId.isNotEmpty ? deviceId : _deviceId,
      'sdp': 'v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=sendrecv\r\n',
    }));

    // Bound the handshake so a dead backend surfaces as a connect failure.
    return answer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw const SessionConnectException('signaling timeout'),
    );
  }

  @override
  Future<bool> runProbe() async {
    // Audio-only demo: outbound audio is always available via flutter_tts on
    // the resident phone, so two-way mode engages (FR-6.4a).
    return true;
  }

  @override
  Future<void> close() async {
    try {
      _channel?.sink.add(jsonEncode(<String, String>{'type': 'end'}));
      await _channel?.sink.close();
    } catch (_) {
      // Already closing; ignore.
    }
    _channel = null;
  }

  Future<void> dispose() => _events.close();
}

// ---------------------------------------------------------------------------
// MockAsrStreamClient — streams live captions from the backend /asr/stream.
// ---------------------------------------------------------------------------

/// Opens the backend /asr/stream WebSocket and converts each caption frame into
/// a [CaptionResult] on the [captions] stream that the CaptionPump consumes.
/// The visitor's speech (captured by phone_doorbell.html and relayed to Amazon
/// Transcribe by the backend) arrives here as partial and final results.
///
/// The WebSocket is opened lazily on the first [captions] subscription so the
/// CaptionPump can subscribe first (in initState) and the connection happens
/// automatically — no external start() call needed from the session host.
class MockAsrStreamClient implements AsrStreamClient {
  MockAsrStreamClient({String? backendWsBase, NowMs? nowMs})
      : _wsBase = backendWsBase ?? DemoConfig.wsBase,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final String _wsBase;
  final NowMs _nowMs;

  WebSocketChannel? _channel;
  StreamController<CaptionResult>? _controller;
  bool _started = false;

  @override
  Stream<CaptionResult> get captions {
    // Create the broadcast controller once.
    _controller ??= StreamController<CaptionResult>.broadcast(
      // Auto-start the WebSocket as soon as the first listener subscribes
      // (the CaptionPump subscribes in initState before the session opens).
      onListen: () {
        if (!_started) {
          _started = true;
          // Default device ID and language — overridden via start() if called.
          _openSocket(deviceId: DemoConfig.deviceId, language: 'en-US');
        }
      },
    );
    return _controller!.stream;
  }

  @override
  Future<void> start({required String deviceId, required String language}) async {
    // Called by the session once the real device ID and language are known.
    // Re-open the socket with the correct parameters (close the auto-started
    // one first if it is already running).
    if (_channel != null) {
      try { await _channel!.sink.close(); } catch (_) {}
      _channel = null;
    }
    _controller ??= StreamController<CaptionResult>.broadcast();
    _started = true;
    _openSocket(deviceId: deviceId, language: language);
  }

  void _openSocket({required String deviceId, required String language}) {
    final uri = Uri.parse('$_wsBase/asr/stream?deviceId=$deviceId&lang=$language');
    // Pass the session token via the Sec-WebSocket-Protocol subprotocol (the
    // browser-safe way to pass a credential on a WS that the backend accepts;
    // see ws-auth.ts).
    final protocols = <String>[
      'threshold.session.${DemoConfig.sessionToken}',
    ];
    final channel = WebSocketChannel.connect(uri, protocols: protocols);
    _channel = channel;

    channel.stream.listen(
      (dynamic raw) {
        final msg = _tryDecode(raw);
        if (msg == null) return;
        final transcript = msg['transcript'];
        if (transcript is! String || transcript.isEmpty) return;
        final isFinal = msg['isFinal'] == true;
        final confRaw = msg['confidence'];
        final confidence = confRaw is num ? confRaw.toDouble() : null;
        _controller?.add(
          CaptionResult(
            speaker: CaptionSpeaker.visitor,
            text: transcript,
            isFinal: isFinal,
            timestampMs: _nowMs(),
            confidence: confidence,
          ),
        );
      },
      onError: (Object _) {
        // Caption stream errors degrade gracefully; the session is not killed.
      },
      cancelOnError: false,
    );
  }

  @override
  Future<void> dispose() async {
    try {
      await _channel?.sink.close();
    } catch (_) {}
    await _controller?.close();
    _controller = null;
  }
}

// ---------------------------------------------------------------------------
// BackendBedrockSuggestionPort — POST /replies for Nova Micro suggestions.
// ---------------------------------------------------------------------------

/// Calls the backend POST /replies endpoint (Clarity Mode) which invokes Amazon
/// Nova Micro and returns up to 3 suggestions. On any failure the backend itself
/// returns the fixed safe set, and the SuggestionProvider also has its own
/// fallback, so the reply bar is never empty.
class BackendBedrockSuggestionPort implements BedrockSuggestionPort {
  BackendBedrockSuggestionPort({
    String? backendUrl,
    String? sessionToken,
    http.Client? client,
  })  : _backendUrl = backendUrl ?? DemoConfig.backendUrl,
        _sessionToken = sessionToken ?? DemoConfig.sessionToken,
        _client = client ?? http.Client();

  final String _backendUrl;
  final String _sessionToken;
  final http.Client _client;

  @override
  Future<List<String>> suggest(String visitorText) async {
    final uri = Uri.parse('$_backendUrl/replies');
    final resp = await _client.post(
      uri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Cookie': 'session=$_sessionToken',
      },
      body: jsonEncode(<String, String>{
        'visitorText': visitorText,
        'language': 'en-US',
        'mode': 'clarity',
      }),
    );
    if (resp.statusCode != 200) {
      // Let SuggestionProvider fall back to on-device suggestions.
      throw http.ClientException('replies ${resp.statusCode}', uri);
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is Map && decoded['suggestions'] is List) {
      return (decoded['suggestions'] as List)
          .whereType<String>()
          .take(3)
          .toList();
    }
    return const <String>[];
  }
}

// ---------------------------------------------------------------------------
// MockReplyPort — speaks the chosen reply aloud on the resident phone.
// ---------------------------------------------------------------------------

/// Audio-only reply binding: synthesizes the chosen reply with flutter_tts and
/// plays it on the resident phone. This stands in for the production ARCH-1 path
/// (inject TTS into the doorbell's outbound WebRTC track). For the demo, the
/// spoken reply out of the resident phone is the audible confirmation that the
/// two-way path works end to end.
class MockReplyPort implements ReplyPort {
  MockReplyPort({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.awaitSpeakCompletion(true);
    _configured = true;
  }

  @override
  Future<SpeakOutcome> speak(String text, {void Function()? onPlaybackStart}) async {
    try {
      await _ensureConfigured();
      // Playback begins once synthesis succeeds; fire before the await so the
      // controller enters SPEAKING_AT_DOOR on real playback (HIGH-05).
      onPlaybackStart?.call();
      await _tts.speak(text);
      return SpeakOutcome.spoken;
    } catch (_) {
      // Design 5.3: a synthesis failure is a TTS failure (retry-once handled by
      // the ReplyController).
      return SpeakOutcome.ttsFailed;
    }
  }
}

// ---------------------------------------------------------------------------
// Shared helper
// ---------------------------------------------------------------------------

/// Decode a WebSocket text frame into a JSON map, or null if it is not a map.
Map<String, dynamic>? _tryDecode(dynamic raw) {
  try {
    final String text;
    if (raw is String) {
      text = raw;
    } else if (raw is List<int>) {
      text = utf8.decode(raw);
    } else {
      return null;
    }
    final parsed = jsonDecode(text);
    return parsed is Map<String, dynamic> ? parsed : null;
  } catch (_) {
    return null;
  }
}
