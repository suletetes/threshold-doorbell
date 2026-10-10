// ASR caption source + pump (CRIT-07 app wiring, FR-5.1, FR-5.3, FR-5.6; AT-4).
//
// The audit found that SessionController.ingestCaption had NO caller: the
// caption surface always rendered the empty placeholder because nothing fed it,
// and there was no ASR client at all. This file is the wiring that closes that
// gap against an injectable engine:
//
//   * CaptionSource is the one interface a caption producer implements. It emits
//     a Stream<CaptionResult> (the tested shape the TurnAccumulator consumes).
//   * AsrStreamClient is the Clarity-Mode cloud client (the /asr/stream
//     WebSocket). The REAL WebSocket client is DEFERRED: it needs the backend
//     and a live network, which the sandbox cannot provide. The interface plus a
//     test fake let the caption flow be driven end to end headless.
//   * OnDeviceCaptionSource adapts the on-device AsrEngine (Privacy Mode,
//     FR-5.2) to the same CaptionSource interface so Privacy captions flow
//     through the identical pump with no cloud egress.
//   * CaptionPump subscribes a CaptionSource to a SessionController, calling
//     ingestCaption for each result. ingestCaption already drops results while
//     the EchoGate is closed (FR-5.6) and while transcription is disabled by the
//     compliance fallback (FR-14.3a), so the pump does not re-implement either
//     gate; it just delivers the feed.
//
// The real cloud WebSocket client and the real on-device Whisper engine remain
// deferred (they need the backend / device); everything here is exercised under
// `flutter test` with a scripted fake so captions provably reach the screen.

import 'dart:async';

import '../session/session_controller.dart';
import 'asr_engine.dart';
import 'turn_segmentation.dart';

/// A producer of live caption results (FR-5.3). Clarity Mode streams from the
/// cloud /asr/stream WebSocket; Privacy Mode runs the on-device engine. Both
/// implement this one interface so the pump is mode agnostic.
abstract class CaptionSource {
  /// The live caption results, oldest first. A broadcast or single-subscription
  /// stream is both acceptable; the pump subscribes exactly once.
  Stream<CaptionResult> get captions;

  /// Release any resources (close the socket, stop the engine).
  Future<void> dispose();
}

/// The Clarity-Mode cloud ASR client over the backend /asr/stream WebSocket
/// (FR-5.1). The real client frames inbound PCM to the backend and parses the
/// transcript messages back into [CaptionResult]s. That socket binding is
/// DEFERRED (needs the backend and a live network); this interface is what the
/// composition root depends on, with a fake supplying a scripted feed in tests.
abstract class AsrStreamClient extends CaptionSource {
  /// Open the stream for [deviceId] in the given recognition [language]. The
  /// live client performs the WebSocket handshake here.
  Future<void> start({required String deviceId, required String language});
}

/// Adapts the on-device [AsrEngine] (Privacy Mode, FR-5.2) to a [CaptionSource].
/// It feeds buffered inbound PCM frames to the engine and converts each
/// [OnDeviceResult] to a [CaptionResult] attributed to the visitor. No network
/// I/O happens here (NFR-4): the engine is on device and this adapter only
/// reshapes its results.
class OnDeviceCaptionSource implements CaptionSource {
  OnDeviceCaptionSource(this._engine, {NowMs? nowMs})
      : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AsrEngine _engine;
  final NowMs _nowMs;
  final StreamController<CaptionResult> _out =
      StreamController<CaptionResult>.broadcast();

  @override
  Stream<CaptionResult> get captions => _out.stream;

  /// Feed one inbound PCM frame to the on-device engine and emit any resulting
  /// caption results (Privacy Mode, FR-5.2). Called by the WebView audio tap on
  /// device; driven directly in tests.
  void feedPcm(List<int> pcmFrame) {
    if (!_engine.isReady) return;
    for (final result in _engine.feed(pcmFrame)) {
      _out.add(
        CaptionResult(
          speaker: CaptionSpeaker.visitor,
          text: result.transcript,
          isFinal: result.isFinal,
          timestampMs: _nowMs(),
          confidence: result.confidence,
        ),
      );
    }
  }

  @override
  Future<void> dispose() => _out.close();
}

/// Subscribes a [CaptionSource] to a [SessionController], delivering each
/// caption result to [SessionController.ingestCaption] (CRIT-07). This is the
/// missing caller: once attached, live captions reach the surface. The echo
/// gate (FR-5.6) and the transcription-disabled compliance fallback (FR-14.3a)
/// are enforced inside ingestCaption, so the pump does not duplicate them.
class CaptionPump {
  CaptionPump({required this.controller, required this.source});

  final SessionController controller;
  final CaptionSource source;

  StreamSubscription<CaptionResult>? _sub;

  /// Begin pumping. Idempotent: a second start is a no-op.
  void start() {
    _sub ??= source.captions.listen(controller.ingestCaption);
  }

  /// Stop pumping and release the subscription. Does not dispose the source
  /// (the owner decides when the socket/engine is torn down).
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}

/// Deterministic fake Clarity-Mode client for tests. Emits a scripted sequence
/// of caption results (optionally with inter-result delays via [emit]). Records
/// that no real socket was opened: proving the wiring without the deferred
/// backend. Also usable as a plain [CaptionSource].
class FakeAsrStreamClient implements AsrStreamClient {
  FakeAsrStreamClient({List<CaptionResult>? script}) : _script = script;

  final List<CaptionResult>? _script;
  final StreamController<CaptionResult> _out =
      StreamController<CaptionResult>.broadcast();

  bool started = false;
  String? startedDeviceId;
  String? startedLanguage;

  @override
  Stream<CaptionResult> get captions => _out.stream;

  @override
  Future<void> start({required String deviceId, required String language}) async {
    started = true;
    startedDeviceId = deviceId;
    startedLanguage = language;
    final script = _script;
    if (script != null) {
      for (final result in script) {
        _out.add(result);
      }
    }
  }

  /// Push a single caption result (test helper for interleaved timing).
  void emit(CaptionResult result) => _out.add(result);

  @override
  Future<void> dispose() => _out.close();
}
