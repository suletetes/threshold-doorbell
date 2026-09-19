// Degradation matrix (Task 26, NFR-5, FR-15.4; AT-20). For each external
// dependency, this defines the graceful degradation the app applies on failure
// and asserts two invariants: no session crashes, and no dependency failure is
// silent (there is always a surfaced, dash-free explanation). Pure logic so the
// whole matrix is exhaustively unit-testable without a device.
//
// Dependencies and their defined degradations (design §6, NFR-5):
//   Bedrock          -> fall back to the fixed safe reply set within 2 s, keep
//                       the reply bar usable (FR-7.3, FR-7.5).
//   Transcribe       -> reconnect with at most 2 s replay; if reconnect fails,
//                       end captions with an explicit notice and suggest Privacy
//                       Mode for the next session, without switching mode
//                       mid-session (design §6, FR-10.1).
//   push             -> foreground paginated poll fallback (FR-3.5).
//   visual processor -> presence falls back to the event condition alone
//                       (FR-5.4); captions and session are unaffected.
//   backend/signaling-> new sessions unavailable with an explanation; cached
//                       history stays usable; the active session is not crashed
//                       (FR-15.4, design §1 accepted single point of failure).

import 'package:flutter/foundation.dart';

/// The external dependencies whose failure must degrade gracefully (NFR-5).
enum Dependency { bedrock, transcribe, push, visualProcessor, backendSignaling }

/// The defined degraded behavior for a failed dependency (NFR-5, design §6).
@immutable
class Degradation {
  const Degradation({
    required this.dependency,
    required this.sessionSurvives,
    required this.userMessage,
    required this.fallbackDescription,
  });

  final Dependency dependency;

  /// Whether the active session keeps running through this failure. Only the
  /// backend/signaling failure prevents NEW sessions; it does not crash an
  /// active one (FR-15.4). No failure ever crashes a session (NFR-5).
  final bool sessionSurvives;

  /// The surfaced, plain-language explanation (no silent failure, NFR-5).
  /// Dash-free (NFR-10).
  final String userMessage;

  /// A short description of the fallback path taken.
  final String fallbackDescription;

  /// No dependency failure is silent: there is always a user message (NFR-5).
  bool get isSurfaced => userMessage.trim().isNotEmpty;
}

/// The defined degradation for [dependency] on failure (NFR-5, design §6). Total
/// over the enum, so every dependency has a defined, non-silent behavior.
Degradation degradationFor(Dependency dependency) {
  switch (dependency) {
    case Dependency.bedrock:
      return const Degradation(
        dependency: Dependency.bedrock,
        sessionSurvives: true,
        userMessage: 'Suggested replies are limited right now. The safe replies '
            'are still available.',
        fallbackDescription: 'Fixed safe reply set within 2 seconds (FR-7.3).',
      );
    case Dependency.transcribe:
      return const Degradation(
        dependency: Dependency.transcribe,
        sessionSurvives: true,
        userMessage: 'Captions stopped. Try Privacy Mode for your next session '
            'to caption on your phone.',
        fallbackDescription:
            'Reconnect with at most 2 seconds replay; on repeated failure end '
            'captions with a notice and suggest Privacy Mode next session, '
            'without switching mode mid session (design §6, FR-10.1).',
      );
    case Dependency.push:
      return const Degradation(
        dependency: Dependency.push,
        sessionSurvives: true,
        userMessage: 'Live alerts are unavailable. Recent events show when you '
            'open the app.',
        fallbackDescription: 'Foreground paginated poll fallback (FR-3.5).',
      );
    case Dependency.visualProcessor:
      return const Degradation(
        dependency: Dependency.visualProcessor,
        sessionSurvives: true,
        userMessage: 'Visitor presence cues are limited. Captions are not '
            'affected.',
        fallbackDescription:
            'Presence falls back to the event condition alone (FR-5.4).',
      );
    case Dependency.backendSignaling:
      return const Degradation(
        dependency: Dependency.backendSignaling,
        sessionSurvives: true,
        userMessage: 'Live sessions are temporarily unavailable. Your saved '
            'history is still here.',
        fallbackDescription:
            'New sessions unavailable; cached history usable; active session not '
            'crashed (FR-15.4, design §1 single point of failure).',
      );
  }
}

/// The full matrix: the defined degradation for every dependency (NFR-5).
List<Degradation> degradationMatrix() =>
    Dependency.values.map(degradationFor).toList();
