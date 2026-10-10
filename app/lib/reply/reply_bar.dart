// Reply bar widget (Task 15, FR-6.1, FR-6.3, FR-6.5, FR-7.2, FR-7.5, G3; AT-5,
// AT-7). Renders at most 3 contextual suggestions plus the fixed safe set plus a
// free-text field (FR-7.5), wired to the ReplyController. While a reply plays it
// shows "Speaking at your door" and disables resubmission (FR-6.3). The whole
// bar is hidden when outbound audio is unavailable; the Captions-Only banner is
// shown instead by the Captions-Only screen (Task 17). Every control carries a
// Semantics label and the bar is fully operable with a screen reader (G4).
//
// --- Presentation (UI/UX audit section 4, "Feedback states") ----------------
//
// The finding that mattered most here: "Success: no success affordance at all.
// 'Speaking at your door' is a text state with no completion cue, which matters
// because the user cannot hear that the reply played."
//
// That is the gap this closes. When a reply finishes playing at the door, the bar
// now confirms it with a success banner naming the reply that played. It is the
// only channel this user has for that fact. The confirmation persists until the
// resident starts composing again rather than expiring on a timer: a cue that
// vanishes on its own is a cue someone can miss, which defeats the point.
//
// Also gone: the 0xFF15151B bar fill, the 0xFFFFCDD2 error text, the 0xFF9E9E9E
// hint, the 0xFF23232B field fill, the 0xFF1565C0 speaking bar, and the raw
// fontSize of 18. The suggestions are real buttons at the 48dp floor instead of
// 32dp chips.

import 'package:flutter/material.dart';

import '../design/colors.dart';
import '../design/components/components.dart';
import '../design/tokens.dart';
import 'reply_controller.dart';
import 'reply_suggestions.dart';

/// The completion cue shown after a reply has played at the door. Dash-free
/// (NFR-10).
String replyPlayedConfirmation(String reply) => 'Played at your door: $reply';

/// The in-flight label while reply audio is playing (FR-6.3). Dash-free.
const String kSpeakingAtDoorLabel = 'Speaking at your door';

/// The static stand in for the speaking spinner under reduced motion.
const IconData kSpeakingStaticIcon = Icons.graphic_eq;

class ReplyBar extends StatefulWidget {
  const ReplyBar({
    super.key,
    required this.controller,
    this.contextualSuggestions = const <String>[],
  });

  final ReplyController controller;

  /// Up to 3 contextual suggestions (Bedrock or on-device). The fixed safe set
  /// is always appended by [composeReplyButtons]. The composition root supplies
  /// live suggestions via the controller; this field is a static fallback used
  /// by presentation tests.
  final List<String> contextualSuggestions;

  @override
  State<ReplyBar> createState() => _ReplyBarState();
}

class _ReplyBarState extends State<ReplyBar> {
  final TextEditingController _text = TextEditingController();

  /// The reply that most recently finished playing at the door, or null.
  ///
  /// Held in the widget rather than the controller because it is a presentation
  /// concern: the controller correctly returns to composing as soon as the reply
  /// is sent, so the SENT state is never on screen long enough to be seen. This
  /// does not change the controller's behavior in any way.
  String? _playedReply;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _clearPlayedConfirmation() {
    if (_playedReply == null) return;
    setState(() => _playedReply = null);
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

        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        // Prefer the controller's live suggestions (set by the composition root
        // from the suggestion provider, FR-7.1a) so they repaint on notify;
        // fall back to the static widget field used by presentation tests.
        final List<String> contextual = c.contextualSuggestions.isNotEmpty
            ? c.contextualSuggestions
            : widget.contextualSuggestions;
        final buttons = composeReplyButtons(contextual);
        final busy = c.state == ReplyState.synthesizing;
        final String? errorMessage = c.errorMessage;
        final String? played = _playedReply;

        return Semantics(
          container: true,
          label: 'Reply options',
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Padding(
              key: const ValueKey('reply-bar'),
              padding: const EdgeInsets.all(Spacing.space3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // The completion cue (audit section 4: there was no success
                  // affordance at all, and this user cannot hear the reply play).
                  AnimatedSize(
                    duration: motionDuration(context, Motion.standard),
                    curve: Motion.standardCurve,
                    alignment: Alignment.topCenter,
                    child: played == null
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding:
                                const EdgeInsets.only(bottom: Spacing.space3),
                            child: StatusBanner(
                              key: const ValueKey('reply-played'),
                              variant: StatusVariant.success,
                              icon: Icons.volume_up_outlined,
                              message: replyPlayedConfirmation(played),
                            ),
                          ),
                  ),
                  if (c.state == ReplyState.error && errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.space3),
                      child: StatusBanner(
                        key: const ValueKey('reply-error'),
                        variant: StatusVariant.danger,
                        message: errorMessage,
                      ),
                    ),
                  Wrap(
                    spacing: Spacing.space2,
                    runSpacing: Spacing.space2,
                    children: <Widget>[
                      for (final s in buttons)
                        _SuggestionButton(
                          label: s,
                          onTap: busy
                              ? null
                              : () => _send(s, ReplySource.template),
                        ),
                    ],
                  ),
                  const SizedBox(height: Spacing.space3),
                  Row(
                    children: <Widget>[
                      Expanded(
                        // One text-field node (MED-04): the TextField already
                        // exposes a text-field semantics node; the label comes
                        // from InputDecoration.labelText rather than an outer
                        // Semantics(textField:) wrapper that added a second node.
                        child: TextField(
                          key: const ValueKey('reply-freetext'),
                          controller: _text,
                          enabled: !busy,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurface),
                          decoration: InputDecoration(
                            labelText: 'Type a reply',
                            hintText: 'Type a reply',
                            hintStyle: theme.textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                            filled: true,
                            fillColor: scheme.surfaceContainerHighest,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: Spacing.space4,
                              vertical: Spacing.space3,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: Radii.roundedMedium,
                              borderSide: BorderSide(color: scheme.outline),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: Radii.roundedMedium,
                              borderSide: BorderSide(color: scheme.outline),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: Radii.roundedMedium,
                              borderSide:
                                  BorderSide(color: scheme.primary, width: 2),
                            ),
                          ),
                          // Starting a new reply retires the previous one's cue.
                          onChanged: (_) => _clearPlayedConfirmation(),
                          onSubmitted: (v) => _send(v, ReplySource.freetext),
                        ),
                      ),
                      const SizedBox(width: Spacing.space2),
                      Semantics(
                        button: true,
                        label: 'Send reply',
                        // Real tap action for TalkBack double-tap (HIGH-06);
                        // null while busy so it matches the disabled button.
                        onTap: busy
                            ? null
                            : () => _send(_text.text, ReplySource.freetext),
                        excludeSemantics: true,
                        child: FilledButton.icon(
                          key: const ValueKey('reply-send'),
                          onPressed: busy
                              ? null
                              : () => _send(_text.text, ReplySource.freetext),
                          icon: const Icon(Icons.send_rounded,
                              size: Spacing.space5),
                          label: const Text('Send'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _send(String text, ReplySource source) async {
    if (!widget.controller.canSend(text)) return;
    _clearPlayedConfirmation();
    await widget.controller.send(text, source: source);
    // Read the outcome BEFORE reset(), which returns the bar to composing.
    final played =
        widget.controller.state == ReplyState.sent ? text.trim() : null;
    if (source == ReplySource.freetext) _text.clear();
    // After a sent/error reply, return to composing so the bar is usable again.
    widget.controller.reset();
    if (played != null && mounted) {
      setState(() => _playedReply = played);
    }
  }
}

/// One suggested reply. A real button at the theme's 48dp minimum rather than a
/// 32dp Material chip (audit section 4, "Touch targets and gestures": nothing in
/// the codebase asserted the minimum).
class _SuggestionButton extends StatelessWidget {
  const _SuggestionButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Reply: $label',
      onTap: onTap,
      excludeSemantics: true,
      child: FilledButton.tonal(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, TouchTarget.minimum),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.space4,
            vertical: Spacing.space2,
          ),
          shape: const StadiumBorder(),
        ),
        child: Text(label),
      ),
    );
  }
}

/// "Speaking at your door" state (FR-6.3). Resubmission is disabled: there are
/// no controls here, so the same reply cannot be sent again while it plays.
///
/// Deliberately not a StatusBanner: this is a transient in-flight progress state
/// carrying a spinner, not a status message with an optional action. It does use
/// the `live` semantic role, because that is exactly what it reports, active
/// two-way audio.
class _SpeakingBanner extends StatelessWidget {
  const _SpeakingBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final live = ThresholdSemanticColors.of(context).live;
    return Semantics(
      liveRegion: true,
      label: kSpeakingAtDoorLabel,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
              live.withValues(alpha: 0.18), scheme.surfaceContainerLow),
          border: Border(top: BorderSide(color: live, width: 2)),
        ),
        child: Padding(
          key: const ValueKey('speaking-banner'),
          padding: const EdgeInsets.all(Spacing.space4),
          child: Row(
            children: <Widget>[
              // Reduced motion gets a static marker instead of a spinner. The
              // live region already announces the state in words, so nothing is
              // lost and nothing moves.
              if (prefersReducedMotion(context))
                Icon(kSpeakingStaticIcon, size: Spacing.space5, color: live)
              else
                SizedBox(
                  width: Spacing.space5,
                  height: Spacing.space5,
                  child: CircularProgressIndicator(strokeWidth: 2, color: live),
                ),
              const SizedBox(width: Spacing.space3),
              Expanded(
                child: Text(
                  kSpeakingAtDoorLabel,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: scheme.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
