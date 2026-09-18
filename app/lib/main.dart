import 'package:flutter/material.dart';

/// Threshold — a two-way captioned Ring doorbell for deaf and hard-of-hearing
/// residents.
///
/// This is the entry point of the skeleton. Real screens live under lib/ui/.
/// Before wiring any UI, complete the audio spike in lib/reply/audio_spike.dart
/// (see docs/hackathon/threshold-spec.md §9 R1) — it is the go/no-go for the
/// whole architecture.
void main() {
  runApp(const ThresholdApp());
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
      home: const _PlaceholderHome(),
    );
  }
}

class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Threshold')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Skeleton ready.\n\n'
            'Next step: the audio spike (lib/reply/audio_spike.dart). Prove a '
            'synthesised voice can be sent out of the doorbell before building '
            'any screens.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}
