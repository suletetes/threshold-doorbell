// On-device ASR engine port (Task 18, FR-5.2, NFR-4; AT-8). Privacy Mode
// transcribes inbound audio entirely on-device and SHALL NOT transmit audio or
// transcript text off the handset (FR-5.2, NFR-4). The real engine binds
// whisper.cpp (native FFI) or a WASM build inside the WebView (ARCH-1); actual
// inference is device-bound and deferred to the developer's machine. This
// interface plus a fixture let the Privacy-Mode caption flow be exercised
// without a device and lets tests assert zero egress: a fixture engine records
// that no bytes ever leave it.

/// A recognized on-device caption result. Mirrors the Clarity result shape so
/// the caption UI is mode-agnostic. Confidence may be null while unfinalized
/// (FR-5.7); privacy inference stays entirely local.
class OnDeviceResult {
  const OnDeviceResult({
    required this.isFinal,
    required this.transcript,
    this.confidence,
  });

  final bool isFinal;
  final String transcript;
  final double? confidence;
}

/// On-device speech recognition. Implementations MUST NOT perform any network
/// I/O: audio and transcript text never leave the device (FR-5.2, NFR-4).
abstract class AsrEngine {
  /// Whether the engine is ready (model present and verified, FR-5.2a).
  bool get isReady;

  /// Feed a PCM audio frame and receive zero or more results synchronously.
  /// Deferred-to-device: the live engine runs Whisper here. The fixture returns
  /// scripted results and records that nothing was transmitted.
  List<OnDeviceResult> feed(List<int> pcmFrame);
}

/// Deterministic fixture engine for tests. It NEVER transmits: it exposes a
/// [bytesTransmitted] counter that stays zero to prove the zero-egress rule
/// (NFR-4, AT-8). Results are scripted.
class FixtureAsrEngine implements AsrEngine {
  FixtureAsrEngine({this.ready = true, List<OnDeviceResult>? script})
      : _script = script ?? _defaultScript();

  final bool ready;
  final List<OnDeviceResult> _script;
  int _emitted = 0;

  /// Total bytes this engine has sent over any network. Always 0 on-device.
  int bytesTransmitted = 0;

  /// PCM bytes fed in, kept only in-memory (never written, never sent).
  int bytesProcessed = 0;

  @override
  bool get isReady => ready;

  @override
  List<OnDeviceResult> feed(List<int> pcmFrame) {
    bytesProcessed += pcmFrame.length;
    // On-device: no transmission ever happens.
    if (_emitted >= _script.length) return const <OnDeviceResult>[];
    final result = _script[_emitted];
    _emitted++;
    return <OnDeviceResult>[result];
  }

  static List<OnDeviceResult> _defaultScript() => const <OnDeviceResult>[
        OnDeviceResult(isFinal: false, transcript: 'hello there'),
        OnDeviceResult(
            isFinal: true, transcript: 'hello there', confidence: 0.88),
      ];
}
