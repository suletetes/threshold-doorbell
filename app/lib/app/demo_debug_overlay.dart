// Demo debug overlay + ring listener (DEMO=true only).
//
// Two jobs in one widget:
//   1. Ring listener: subscribes to DemoHub.onRing and calls [onRing] so the
//      home screen can auto-open the session when the visitor presses Ring.
//   2. Debug panel: a collapsible floating panel showing the last N
//      [THRESHOLD] log lines, the hub connection status, and an editable
//      backend URL field (persisted so a new domain never needs a rebuild).
//
// Wrap the home screen body with [DemoDebugOverlay]. It is inert unless
// DemoConfig.enabled is true.

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mock_adapters.dart';

const String _kBackendUrlPrefKey = 'demo_backend_url_override';

class DemoDebugOverlay extends StatefulWidget {
  const DemoDebugOverlay({
    super.key,
    required this.child,
    required this.onRing,
  });

  final Widget child;

  /// Called when the visitor presses Ring on Phone A.
  final void Function() onRing;

  @override
  State<DemoDebugOverlay> createState() => _DemoDebugOverlayState();
}

class _DemoDebugOverlayState extends State<DemoDebugOverlay> {
  final Queue<String> _lines = Queue<String>();
  static const int _maxLines = 60;
  bool _expanded = false;
  bool _visitorOnline = false;
  bool _hubConnected = false;

  StreamSubscription<void>? _ringSub;
  StreamSubscription<bool>? _presenceSub;
  final TextEditingController _urlCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (!DemoConfig.enabled) return;

    _loadBackendOverride();

    // Route all [THRESHOLD] logs into the panel.
    demoLogSink = (line) {
      if (!mounted) return;
      setState(() {
        _lines.addLast(line);
        while (_lines.length > _maxLines) {
          _lines.removeFirst();
        }
        _hubConnected = DemoHub.instance.isConnected;
        _visitorOnline = DemoHub.instance.visitorOnline;
      });
    };

    // Connect the hub and listen for ring + presence.
    DemoHub.instance.connect();
    _ringSub = DemoHub.instance.onRing.listen((_) {
      if (mounted) widget.onRing();
    });
    _presenceSub = DemoHub.instance.visitorPresence.listen((online) {
      if (mounted) setState(() => _visitorOnline = online);
    });

    _urlCtrl.text = DemoConfig.backendUrl;
  }

  Future<void> _loadBackendOverride() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kBackendUrlPrefKey);
      if (saved != null && saved.isNotEmpty) {
        DemoConfig.backendUrl = saved;
        if (mounted) _urlCtrl.text = saved;
      }
    } catch (_) {}
  }

  Future<void> _saveBackendOverride(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kBackendUrlPrefKey, url);
    } catch (_) {}
    DemoConfig.backendUrl = url;
    DemoHub.instance.dispose();
    DemoHub.instance.connect();
  }

  @override
  void dispose() {
    _ringSub?.cancel();
    _presenceSub?.cancel();
    _urlCtrl.dispose();
    if (demoLogSink != null) demoLogSink = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!DemoConfig.enabled) return widget.child;

    return Stack(
      children: <Widget>[
        widget.child,
        // Floating status chip / debug toggle (bottom-right).
        Positioned(
          right: 8,
          bottom: 8,
          child: SafeArea(
            child: _expanded ? _panel(context) : _chip(context),
          ),
        ),
      ],
    );
  }

  Widget _chip(BuildContext context) {
    final color = _hubConnected
        ? (_visitorOnline ? Colors.green : Colors.orange)
        : Colors.red;
    return GestureDetector(
      onTap: () => setState(() => _expanded = true),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.bug_report, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              _hubConnected ? (_visitorOnline ? 'hub+visitor' : 'hub only') : 'offline',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: size.width * 0.92,
        height: size.height * 0.5,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.circle,
                  size: 12,
                  color: _hubConnected
                      ? (_visitorOnline ? Colors.green : Colors.orange)
                      : Colors.red,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _hubConnected
                        ? (_visitorOnline
                            ? 'Hub connected, visitor online'
                            : 'Hub connected, waiting for visitor')
                        : 'Hub offline',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _lines.clear()),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.delete_outline, color: Colors.white54, size: 18),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _expanded = false),
                  child: const Icon(Icons.close, color: Colors.white54, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Editable backend URL.
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _urlCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Backend URL',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 11),
                      filled: true,
                      fillColor: Colors.white10,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _saveBackendOverride(_urlCtrl.text.trim()),
                  child: const Text('Apply', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Log lines.
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ListView(
                  reverse: true,
                  children: _lines
                      .toList()
                      .reversed
                      .map((l) => Text(
                            l,
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
