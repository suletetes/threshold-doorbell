// Reply bar widget (Task 15, FR-6.1, FR-6.3, FR-6.5, FR-7.2, FR-7.5, G3; AT-5,
// AT-7). Renders at most 3 contextual suggestions plus the fixed safe set plus a
// free-text field (FR-7.5), wired to the ReplyController. While a reply plays it
// shows "Speaking at your door" and disables resubmission (FR-6.3). The whole
// bar is hidden when outbound audio is unavailable; the Captions-Only banner is
// shown instead by the Captions-Only screen (Task 17). Every control carries a
// Semantics label and the bar is fully operable with a screen reader (G4).

import 'package:flutter/material.dart';

import 'reply_controller.dart';
import 'reply_suggestions.dart';

class ReplyBar extends StatefulWidget {
  const ReplyBar({
    super.key,
    required this.controller,
    required this.contextualSuggestions,
  });

  final ReplyController controller;

  /// Up to 3 contextual suggestions (Bedrock or on-device). The fixed safe set
  /// is always appended by [composeReplyButtons].
  final List<String> contextualSuggestions;

  @override
  State<ReplyBar> createState() => _ReplyBarState();
}

class _ReplyBarState extends State<ReplyBar> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        // Hidden entirely when outbound audio is unavailable (FR-6.4).
        if (!c.replyBarVisible) return const SizedBox.shrink();

        if (c.state == ReplyState.speakingAtDoor) {
          return _SpeakingBanner(text: c.inFlightText ?? '');
        }

        final buttons = composeReplyButtons(widget.contextualSuggestions);
        final busy = c.state == ReplyState.synthesizing;
        return Semantics(
          container: true,
          label: 'Reply options',
          child: Container(
            key: const ValueKey('reply-bar'),
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF15151B),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (c.state == ReplyState.error && c.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Semantics(
                      liveRegion: true,
                      label: c.errorMessage!,
                      child: Text(
                        c.errorMessage!,
                        style: const TextStyle(color: Color(0xFFFFCDD2)),
                      ),
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final s in buttons)
                      _SuggestionChip(
                        label: s,
                        onTap: busy ? null : () => _send(s, ReplySource.template),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Semantics(
                        textField: true,
                        label: 'Type a reply',
                        child: TextField(
                          key: const ValueKey('reply-freetext'),
                          controller: _text,
                          enabled: !busy,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'Type a reply',
                            hintStyle: TextStyle(color: Color(0xFF9E9E9E)),
                            filled: true,
                            fillColor: Color(0xFF23232B),
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (v) => _send(v, ReplySource.freetext),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Semantics(
                      button: true,
                      label: 'Send reply',
                      excludeSemantics: true,
                      child: FilledButton(
                        key: const ValueKey('reply-send'),
                        onPressed: busy
                            ? null
                            : () => _send(_text.text, ReplySource.freetext),
                        child: const Text('Send'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _send(String text, ReplySource source) async {
    if (!widget.controller.canSend(text)) return;
    await widget.controller.send(text, source: source);
    if (source == ReplySource.freetext) _text.clear();
    // After a sent/error reply, return to composing so the bar is usable again.
    widget.controller.reset();
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Reply: $label',
      excludeSemantics: true,
      child: ActionChip(
        label: Text(label),
        onPressed: onTap,
      ),
    );
  }
}

/// "Speaking at your door" state (FR-6.3). Resubmission is disabled: there are
/// no controls here, so the same reply cannot be sent again while it plays.
class _SpeakingBanner extends StatelessWidget {
  const _SpeakingBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Speaking at your door',
      child: Container(
        key: const ValueKey('speaking-banner'),
        padding: const EdgeInsets.all(16),
        color: const Color(0xFF1565C0),
        child: const Row(
          children: <Widget>[
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text(
              'Speaking at your door',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
