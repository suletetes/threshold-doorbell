// Demo mock adapters — DEMO=true build (two-phone WiFi doorbell demo).
//
// All three adapters share ONE WebSocket to /demo/hub (role=resident). The hub
// relays messages between this phone (resident) and the visitor page (Phone A):
//
//   incoming {type:'ring'}                 -> DemoHub.onRing fires (app shows alert)
//   incoming {type:'caption', text, isFinal}-> pushed to the caption stream
//   outgoing {type:'answer'}               -> sent when the resident answers
//   outgoing {type:'reply', text}          -> sent when the resident picks a reply
//
// Why a shared hub: SessionPort, CaptionSource and ReplyPort are three separate
// interfaces, but the demo needs ONE connection carrying all message types.
// DemoHub is a singleton the three adapters read from / write to.
//
// Trusted transport: BACKEND_URL is https://threshold-demo.duckdns.org, so
// wss:// uses a real Let's Encrypt cert — no self-signed cert problems.
//
// Every step logs with [THRESHOLD] to the debug console and to the in-app
// debug panel (see DemoHub.logSink).

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../captions/asr_client.dart';
import '../captions/turn_segmentation.dart';
import '../reply/reply_port.dart';
import '../reply/suggestion_provider.dart';
import '../session/session_port.dart';

typedef NowMs = int Function();

// ---------------------------------------------------------------------------
// Debug log — console + optional in-app sink (set by the debug panel).
// ---------------------------------------------------------------------------
void Function(String line)? demoLogSink;

void _log(String msg) {
  final line = '[THRESHOLD] $msg';
  dev.log(line, name: 'threshold');
  // ignore: avoid_print
  print(line);
  try {
    demoLogSink?.call(msg);
  } catch (_) {}
}

// ---------------------------------------------------------------------------
// Demo configuration (compile-time --dart-define values).
// ---------------------------------------------------------------------------
class DemoConfig {
  static const bool enabled = bool.fromEnvironment('DEMO', defaultValue: false);

  /// Overridable at runtime by the debug panel (shared_preferences). Falls back
  /// to the compile-time value.
  static String? _runtimeBackendUrl;

  static String get backendUrl =>
      _runtimeBackendUrl ??
      const String.fromEnvironment(
        'BACKEND_URL',
        defaultValue: 'https://threshold-demo.duckdns.org',
      );

  static set backendUrl(String url) => _runtimeBackendUrl = url.replaceAll(RegExp(r'/+$'), '');

  static const String deviceId =
      String.fromEnvironment('DEVICE_ID', defaultValue: 'mock-doorbell-001');

  static String get wsBase => backendUrl.replaceFirst(RegExp(r'^http'), 'ws');

  static void logConfig() {
    _log('=== DemoConfig ===');
    _log('  DEMO       : $enabled');
    _log('  BACKEND_URL: $backendUrl');
    _log('  WS_BASE    : $wsBase');
    _log('  DEVICE_ID  : $deviceId');
  }
}

// ---------------------------------------------------------------------------
// DemoHub — the single shared WebSocket to /demo/hub (role=resident).
// ---------------------------------------------------------------------------
class DemoHub {
  DemoHub._();
  static final DemoHub instance = DemoHub._();

  WebSocketChannel? _channel;
  bool _connected = false;
  bool _connecting = false;

  /// Fired when the visitor presses Ring.
  final _ringController = StreamController<void>.broadcast();
  Stream<void> get onRing => _ringController.stream;

  /// Fired when the visitor ends the call, so the resident session can close.
  final _hangupController = StreamController<void>.broadcast();
  Stream<void> get onHangup => _hangupController.stream;

  /// Live captions from the visitor's speech.
  final _captionController = StreamController<CaptionResult>.broadcast();
  Stream<CaptionResult> get captions => _captionController.stream;

  /// Presence: true when the visitor page is connected to the same room.
  final _presenceController = StreamController<bool>.broadcast();
  Stream<bool> get visitorPresence => _presenceController.stream;
  bool visitorOnline = false;

  bool get isConnected => _connected;

  /// Open the hub connection (idempotent). Safe to call from several adapters;
  /// only the first call connects.
  void connect() {
    if (_connected || _connecting) return;
    _connecting = true;
    DemoConfig.logConfig();
    final url =
        '${DemoConfig.wsBase}/demo/hub?role=resident&deviceId=${Uri.encodeComponent(DemoConfig.deviceId)}';
    _log('HUB connecting -> $url');
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
    } catch (e) {
      _connecting = false;
      _log('HUB connect error: $e');
      return;
    }

    _channel!.stream.listen(
      (dynamic raw) {
        _connected = true;
        _connecting = false;
        final msg = _tryDecode(raw);
        if (msg == null) return;
        final type = msg['type'];
        switch (type) {
          case 'joined':
            _log('HUB joined room "${msg['deviceId']}" as ${msg['role']}');
            break;
          case 'peer-joined':
            if (msg['role'] == 'visitor') {
              visitorOnline = true;
              _presenceController.add(true);
              _log('HUB visitor page connected');
            }
            break;
          case 'peer-left':
            if (msg['role'] == 'visitor') {
              visitorOnline = false;
              _presenceController.add(false);
              _log('HUB visitor page disconnected');
            }
            break;
          case 'ring':
            _log('HUB <- RING from visitor');
            _ringController.add(null);
            break;
          case 'caption':
            final text = msg['text'];
            if (text is String && text.isNotEmpty) {
              final isFinal = msg['isFinal'] == true;
              _log('HUB <- caption ${isFinal ? "FINAL" : "partial"}: "$text"');
              _captionController.add(CaptionResult(
                speaker: CaptionSpeaker.visitor,
                text: text,
                isFinal: isFinal,
                timestampMs: DateTime.now().millisecondsSinceEpoch,
                confidence: 0.95,
              ));
            }
            break;
          case 'hangup':
            _log('HUB <- hangup from visitor');
            _hangupController.add(null);
            break;
          case 'no-peer':
            _log('HUB visitor not connected yet (${msg['forType']} not delivered)');
            break;
        }
      },
      onError: (Object e) {
        _log('HUB stream error: $e');
        _connected = false;
        _scheduleReconnect();
      },
      onDone: () {
        _log('HUB closed');
        _connected = false;
        visitorOnline = false;
        _presenceController.add(false);
        _scheduleReconnect();
      },
      cancelOnError: false,
    );
  }

  void _scheduleReconnect() {
    if (_connecting) return;
    Future<void>.delayed(const Duration(seconds: 3), () {
      _connecting = false;
      connect();
    });
  }

  void send(Map<String, dynamic> obj) {
    final ch = _channel;
    if (ch == null) {
      _log('HUB cannot send ${obj['type']} - not connected');
      return;
    }
    try {
      ch.sink.add(jsonEncode(obj));
      _log('HUB -> ${obj['type']}');
    } catch (e) {
      _log('HUB send error: $e');
    }
  }

  void sendAnswer() => send(<String, dynamic>{'type': 'answer'});
  void sendReply(String text) => send(<String, dynamic>{'type': 'reply', 'text': text});
  void sendHangup() => send(<String, dynamic>{'type': 'hangup'});
  void sendDecline() => send(<String, dynamic>{'type': 'decline'});

  Future<void> dispose() async {
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _connected = false;
  }
}

// ---------------------------------------------------------------------------
// MockSessionPort — "connect" just confirms the hub is up; the hub carries data.
// ---------------------------------------------------------------------------
class MockSessionPort implements SessionPort {
  MockSessionPort() {
    DemoHub.instance.connect();
  }

  final _events = StreamController<SessionPortEvent>.broadcast();

  @override
  Stream<SessionPortEvent> get events => _events.stream;

  @override
  Future<NegotiatedMedia> connect(String deviceId) async {
    _log('SESSION connect (resident answering) deviceId=$deviceId');
    DemoHub.instance.connect();
    // Tell the visitor we answered so it starts captioning.
    DemoHub.instance.sendAnswer();
    _events.add(SessionPortEvent.connected);
    // Audio-only two-way: sendrecv audio, recvonly video, one peer (ARCH-1 shape).
    return const NegotiatedMedia(
      audioDirection: 'sendrecv',
      videoDirection: 'recvonly',
      peerConnectionCount: 1,
    );
  }

  @override
  Future<bool> runProbe() async {
    _log('PROBE -> true (audio-only demo)');
    return true;
  }

  @override
  Future<void> close() async {
    _log('SESSION close');
    DemoHub.instance.sendHangup();
  }

  Future<void> dispose() => _events.close();
}

// ---------------------------------------------------------------------------
// MockAsrStreamClient — captions come from the shared hub, not a separate WS.
// ---------------------------------------------------------------------------
class MockAsrStreamClient implements AsrStreamClient {
  MockAsrStreamClient() {
    DemoHub.instance.connect();
  }

  StreamController<CaptionResult>? _controller;
  StreamSubscription<CaptionResult>? _sub;
  int _count = 0;

  @override
  Stream<CaptionResult> get captions {
    _controller ??= StreamController<CaptionResult>.broadcast(
      onListen: () {
        _log('ASR captions: subscribed to hub caption stream');
        _sub = DemoHub.instance.captions.listen((c) {
          _count++;
          _controller?.add(c);
        });
      },
      onCancel: () => _sub?.cancel(),
    );
    return _controller!.stream;
  }

  @override
  Future<void> start({required String deviceId, required String language}) async {
    _log('ASR start (hub-based, no-op): deviceId=$deviceId language=$language');
    DemoHub.instance.connect();
  }

  @override
  Future<void> dispose() async {
    _log('ASR dispose totalCaptions=$_count');
    await _sub?.cancel();
    await _controller?.close();
    _controller = null;
  }
}

// ---------------------------------------------------------------------------
// MockReplyPort — speak locally AND send the reply to the visitor via the hub.
// ---------------------------------------------------------------------------
class MockReplyPort implements ReplyPort {
  MockReplyPort({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    _log('TTS configuring');
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.awaitSpeakCompletion(true);
    _configured = true;
  }

  @override
  Future<SpeakOutcome> speak(String text, {void Function()? onPlaybackStart}) async {
    _log('REPLY chosen: "$text"');
    // Send to the visitor page so they hear it spoken (the real two-way path).
    DemoHub.instance.sendReply(text);
    try {
      await _ensureConfigured();
      onPlaybackStart?.call();
      await _tts.speak(text);
      _log('TTS ok local playback complete');
      return SpeakOutcome.spoken;
    } catch (e) {
      _log('TTS error: $e');
      // Even if local TTS fails, the visitor still heard it via the hub.
      return SpeakOutcome.spoken;
    }
  }
}

// ---------------------------------------------------------------------------
// BackendBedrockSuggestionPort — POST /replies (Nova Micro smart replies).
// Kept, with a safe fallback set so the reply bar is never empty.
// ---------------------------------------------------------------------------
class BackendBedrockSuggestionPort implements BedrockSuggestionPort {
  BackendBedrockSuggestionPort();

  static const List<String> _safeSet = <String>[
    'Please leave it at the door',
    'One moment please',
    'I will be right there',
  ];

  @override
  Future<List<String>> suggest(String visitorText) async {
    // Call the real backend POST /replies (Amazon Bedrock Nova Micro in Clarity
    // Mode). The demo session token is accepted because the deployed backend
    // runs in the demo environment. A 2 second timeout and any error fall back
    // to the fixed safe set, so the reply bar is never empty or slow (FR-7.3).
    final url = Uri.parse('${DemoConfig.backendUrl}/replies');
    try {
      final res = await http
          .post(
            url,
            headers: <String, String>{
              'content-type': 'application/json',
              'authorization': 'Bearer demo-session-token',
            },
            body: jsonEncode(<String, dynamic>{
              'visitorText': visitorText,
              'language': 'en-US',
              'mode': 'clarity',
            }),
          )
          .timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          final list = decoded['suggestions'];
          if (list is List) {
            final suggestions = list.whereType<String>().toList();
            if (suggestions.isNotEmpty) {
              _log('REPLIES Bedrock suggestions for "$visitorText" -> $suggestions');
              return suggestions;
            }
          }
        }
      }
      _log('REPLIES non-200 or empty (${res.statusCode}) -> safe set');
      return _safeSet;
    } catch (e) {
      _log('REPLIES error ($e) -> safe set');
      return _safeSet;
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
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
