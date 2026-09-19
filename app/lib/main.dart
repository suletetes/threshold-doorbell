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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/home_screen.dart';

void main() {
  runApp(const ProviderScope(child: ThresholdApp()));
}

class ThresholdApp extends StatelessWidget {
  const ThresholdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Threshold',
      // Accessibility is core to this product, not an afterthought:
      // large text, high contrast, full screen-reader support (WCAG 2.2 AA).
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
