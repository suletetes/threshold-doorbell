// ============================================================================
// TASK 2: THE ARCH-1 OUTBOUND-AUDIO SPIKE (do before any WebRTC/reply UI).
//
// Goal: prove a synthesized voice can be injected into the OUTBOUND audio track
// of a Ring WebRTC/WHEP session, from inside a WebView, and reach the doorbell.
// This is the go/no-go gate for the whole product (design ARCH-1, requirement
// FR-6, acceptance test AT-5/AT-6).
//
// ARCH-1: exactly ONE RTCPeerConnection, owned by the WebView (audio sendrecv,
// video recvonly). flutter_webrtc is NOT used for the live session because it
// cannot inject an outbound track (no Insertable Streams on any platform).
//
// The real proving ground is assets asset app/spike/webrtc_audio_spike.html.
// This widget hosts it, forwards a Ring WHEP URL, and surfaces the verdict.
//
// HOW TO RUN (on a device or emulator, with a Ring token):
//   1. flutter pub add webview_flutter   (device-only dep; see runbook)
//   2. Add app/spike/webrtc_audio_spike.html to pubspec assets.
//   3. Put AudioSpikeScreen() as home, flutter run on a real device.
//   4. Paste the Ring WHEP endpoint (obtained from the backend /signaling or the
//      Ring Playground), tap Connect -> Run probe. A PASS verdict proves ARCH-1.
//   5. Tap "Speak test phrase" and confirm it is audible at the doorbell.
//
// Offline harness: leave the WHEP field blank to run a loopback that exercises
// the AudioContext -> replaceTrack -> getStats path without a Ring device.
//
// See app/spike/RUNBOOK.md for the full procedure and the decision it gates.
// ============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';

/// The verdict the WebView reports back over the bridge.
enum SpikeVerdict { notRun, pass, fail }

/// Parses a bridge message (JSON string) from the spike HTML.
/// Pure and unit-testable so the bridge contract is verified without a device.
class SpikeMessage {
  final String type; // 'log' | 'state' | 'probe' | 'verdict'
  final Map<String, dynamic> data;
  const SpikeMessage(this.type, this.data);

  static SpikeMessage parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('bridge message is not a JSON object');
    }
    final type = decoded['type'];
    if (type is! String || type.isEmpty) {
      throw const FormatException('bridge message missing string "type"');
    }
    return SpikeMessage(type, decoded);
  }

  /// Interprets a message into a verdict transition, or null if it does not
  /// change the verdict. Sticky: once pass/fail is set the caller keeps it.
  SpikeVerdict? verdictFrom() {
    if (type == 'verdict') {
      final kind = data['kind'];
      if (kind == 'pass') return SpikeVerdict.pass;
      if (kind == 'fail') return SpikeVerdict.fail;
    }
    if (type == 'probe') {
      final ok = data['outboundAvailable'];
      if (ok == true) return SpikeVerdict.pass;
      if (ok == false) return SpikeVerdict.fail;
    }
    return null;
  }
}

/// Screen that hosts the WebView spike. The WebView import is intentionally NOT
/// referenced here so the app compiles and `flutter test` runs in this sandbox
/// without the device-only webview_flutter dependency. Wire it in on-device per
/// the runbook: replace [_SpikePlaceholder] with a WebViewWidget whose
/// JavaScript channel named 'SpikeBridge' forwards messages to
/// [handleBridgeMessage].
class AudioSpikeScreen extends StatefulWidget {
  const AudioSpikeScreen({super.key});

  @override
  State<AudioSpikeScreen> createState() => _AudioSpikeScreenState();
}

class _AudioSpikeScreenState extends State<AudioSpikeScreen> {
  SpikeVerdict _verdict = SpikeVerdict.notRun;
  final List<String> _log = <String>[];

  /// Bridge entry point. Called for every JS message. Sticky verdict: a pass or
  /// fail is not overwritten by later log/state messages.
  void handleBridgeMessage(String raw) {
    late final SpikeMessage msg;
    try {
      msg = SpikeMessage.parse(raw);
    } on FormatException catch (e) {
      setState(() => _log.add('bridge parse error: ${e.message}'));
      return;
    }
    if (msg.type == 'log') {
      final line = msg.data['line'];
      if (line is String) setState(() => _log.add(line));
    }
    final next = msg.verdictFrom();
    if (next != null && _verdict == SpikeVerdict.notRun) {
      setState(() => _verdict = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ARCH-1 audio spike')),
      body: Column(
        children: <Widget>[
          _VerdictBanner(verdict: _verdict),
          const Expanded(child: _SpikePlaceholder()),
        ],
      ),
    );
  }
}

/// Shown in the sandbox build. On-device, swap this for the WebViewWidget.
class _SpikePlaceholder extends StatelessWidget {
  const _SpikePlaceholder();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Load app/spike/webrtc_audio_spike.html in a WebView on a real device '
          'to run the spike. See app/spike/RUNBOOK.md.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _VerdictBanner extends StatelessWidget {
  final SpikeVerdict verdict;
  const _VerdictBanner({required this.verdict});

  @override
  Widget build(BuildContext context) {
    final (Color color, String label) = switch (verdict) {
      SpikeVerdict.notRun => (const Color(0xFF374151), 'Verdict: not run yet'),
      SpikeVerdict.pass => (const Color(0xFF1B5E20), 'Outbound audio works. ARCH-1 holds.'),
      SpikeVerdict.fail => (const Color(0xFF7F1D1D), 'Outbound audio unavailable. Ship Captions-Only.'),
    };
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.all(16),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
      ),
    );
  }
}
