// Home screen presentation (UI/UX audit C5, "the primary action has no visual
// weight", and section 4, "Information architecture": the Privacy-Mode notice
// sat between the primary and secondary buttons, interrupting the action group).
//
// These tests pin the three structural decisions of the redesign: the hero is
// the first and largest thing on the screen, Settings is an AppBar destination
// rather than a peer of the hero, and the Privacy-Mode notice is a StatusBanner
// below the hero instead of a grey sentence inside the action group.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/app/home_screen.dart';
import 'package:threshold/app/providers.dart';
import 'package:threshold/captions/language_selection.dart';
import 'package:threshold/captions/model_provisioning.dart';
import 'package:threshold/captions/turn_segmentation.dart';
import 'package:threshold/consent/recording_notice.dart';
import 'package:threshold/consent/recording_notice_screen.dart';
import 'package:threshold/design/components/components.dart';
import 'package:threshold/design/theme.dart';
import 'package:threshold/design/tokens.dart';
import 'package:threshold/reply/reply_port.dart';
import 'package:threshold/reply/suggestion_provider.dart';
import 'package:threshold/session/conversation_screen.dart';
import 'package:threshold/session/ring_app_launcher.dart';
import 'package:threshold/session/session_port.dart';
import 'package:threshold/session/session_state.dart';
import 'package:threshold/settings/settings_controller.dart';
import 'package:threshold/settings/settings_screen.dart';

/// A provisioning machine already driven to verified, so Privacy Mode is
/// available and the unavailability banner is absent (FR-5.2a).
ModelProvisioningMachine _verifiedProvisioning() {
  final machine = ModelProvisioningMachine(modelSizeBytes: 1024)
    ..optIn()
    ..startDownload(liveSessionActive: false)
    ..onDownloadComplete()
    ..onVerified(ok: true);
  return machine;
}

/// The base device/consent overrides. The consent store is pre-acknowledged by
/// default (acknowledged: true) so answering the door reaches the session; the
/// CRIT-06 gate test overrides it with an unacknowledged store to prove the gate
/// blocks live use.
List<Override> _overrides({
  bool consentAcknowledged = true,
  BedrockSuggestionPort? bedrock,
  SessionPort? session,
  ModelProvisioningMachine? provisioning,
}) =>
    <Override>[
      sessionPortProvider.overrideWithValue(session ?? FakeSessionPort()),
      replyPortProvider.overrideWithValue(FakeReplyPort()),
      ringAppLauncherProvider.overrideWithValue(FakeRingAppLauncher()),
      bedrockSuggestionPortProvider
          .overrideWithValue(bedrock ?? FakeBedrockSuggestionPort()),
      dataErasurePortProvider.overrideWithValue(FakeDataErasurePort()),
      consentStoreProvider
          .overrideWithValue(FakeConsentStore(acknowledged: consentAcknowledged)),
      if (provisioning != null)
        modelProvisioningProvider.overrideWithValue(provisioning),
    ];

Widget _host({ModelProvisioningMachine? provisioning}) => ProviderScope(
      overrides: _overrides(provisioning: provisioning),
      child: MaterialApp(theme: ThresholdTheme.light(), home: const HomeScreen()),
    );

void main() {
  group('Home hero action (audit C5)', () {
    testWidgets('the answer action is a PrimaryActionCard with a doorbell icon',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pump();
      expect(find.byKey(const ValueKey('home-answer')), findsOneWidget);
      expect(find.byType(PrimaryActionCard), findsOneWidget);
      expect(find.byIcon(Icons.doorbell_outlined), findsOneWidget);
      expect(find.text('Answer the door'), findsOneWidget);
      expect(find.text(kHomeHeroSupportingLine), findsOneWidget);
    });

    testWidgets('the hero dominates: it is far taller than the Settings action',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pump();
      final hero = tester.getSize(find.byKey(const ValueKey('home-answer')));
      final settings = tester.getSize(find.byKey(const ValueKey('home-settings')));
      expect(hero.height, greaterThanOrEqualTo(PrimaryActionCard.minimumHeight));
      expect(hero.height, greaterThan(settings.height));
      // It is also the widest thing: it stretches the content column.
      expect(hero.width, greaterThan(settings.width));
    });

    testWidgets('the hero is the first thing below the app bar', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pump();
      final heroTop = tester.getTopLeft(find.byKey(const ValueKey('home-answer'))).dy;
      final explanationTop = tester.getTopLeft(find.text(kHomeReadyExplanation)).dy;
      // The paragraph used to come first. Recognition over recall: action first.
      expect(heroTop, lessThan(explanationTop));
    });
  });

  group('Settings is an app bar destination (audit C5)', () {
    testWidgets('it lives in the AppBar actions, not in the body', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byKey(const ValueKey('home-settings')),
        ),
        findsOneWidget,
      );
      // No stock OutlinedButton peer of the hero remains.
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('it meets the 48dp minimum target', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pump();
      final size = tester.getSize(find.byKey(const ValueKey('home-settings')));
      expect(size.height, greaterThanOrEqualTo(TouchTarget.minimum));
      expect(size.width, greaterThanOrEqualTo(TouchTarget.minimum));
    });

    testWidgets('it opens Settings with exactly one app bar', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('home-settings')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      // Settings used to be pushed inside a second Scaffold with a second
      // AppBar, stacking two title bars.
      expect(find.byType(AppBar), findsOneWidget);
    });
  });

  group('Privacy Mode notice (audit section 4, information architecture)', () {
    testWidgets('renders as a StatusBanner below the hero, not between the actions',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pump();
      expect(find.byKey(const ValueKey('home-privacy-unavailable')), findsOneWidget);
      expect(find.byType(StatusBanner), findsOneWidget);
      final heroBottom = tester.getBottomLeft(find.byKey(const ValueKey('home-answer'))).dy;
      final bannerTop = tester.getTopLeft(find.byType(StatusBanner)).dy;
      expect(bannerTop, greaterThanOrEqualTo(heroBottom));
    });

    testWidgets('it is a warning, not an error, and carries the model label',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pump();
      final banner = tester.widget<StatusBanner>(find.byType(StatusBanner));
      expect(banner.variant, StatusVariant.warning);
      expect(banner.message, contains('Privacy Mode'));
      expect(find.byIcon(StatusBanner.iconFor(StatusVariant.warning)), findsOneWidget);
    });

    testWidgets('it disappears once the on device model is verified (FR-5.2a)',
        (tester) async {
      await tester.pumpWidget(_host(provisioning: _verifiedProvisioning()));
      await tester.pump();
      expect(find.byType(StatusBanner), findsNothing);
      expect(find.byKey(const ValueKey('home-privacy-unavailable')), findsNothing);
    });

    testWidgets('it announces itself as a live region (G4)', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host());
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp('Privacy Mode')), findsOneWidget);
      handle.dispose();
    });
  });

  group('Session lifecycle from the host (CRIT-05, probe P8)', () {
    testWidgets('system back ends the session and returns to home, not a blank screen',
        (tester) async {
      final port = FakeSessionPort();
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(session: port, provisioning: _verifiedProvisioning()),
          child: MaterialApp(theme: ThresholdTheme.light(), home: const HomeScreen()),
        ),
      );
      await tester.pump();

      // Answer the door: push the session host and let it reach live.
      await tester.tap(find.byKey(const ValueKey('home-answer')));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationScreen), findsOneWidget);
      expect(port.connectCalls, 1);

      // System back must end the session (close the port) and pop back home,
      // never strand the user on the blank idle media surface (probe P8).
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(port.closeCalls, greaterThanOrEqualTo(1));
      expect(find.byType(ConversationScreen), findsNothing);
      expect(find.byKey(const ValueKey('home-answer')), findsOneWidget);
    });

    testWidgets('tapping End returns to home instead of a blank screen (CRIT-05)',
        (tester) async {
      final port = FakeSessionPort();
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(session: port, provisioning: _verifiedProvisioning()),
          child: MaterialApp(theme: ThresholdTheme.light(), home: const HomeScreen()),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('home-answer')));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationScreen), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('end-session')));
      await tester.pumpAndSettle();

      expect(port.closeCalls, greaterThanOrEqualTo(1));
      expect(find.byType(ConversationScreen), findsNothing);
      expect(find.byKey(const ValueKey('home-answer')), findsOneWidget);
    });
  });

  group('Contextual suggestions are wired (MED-13, FR-7.1a)', () {
    testWidgets('a visitor turn produces Bedrock suggestions in the reply bar',
        (tester) async {
      final port = FakeSessionPort();
      final bedrock = FakeBedrockSuggestionPort(
        scripted: const <String>['Thanks, one moment', 'Leave it there please'],
      );
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(session: port, bedrock: bedrock),
          child: MaterialApp(
            theme: ThresholdTheme.light(),
            home: Consumer(builder: (context, ref, _) {
              capturedRef = ref;
              return const HomeScreen();
            }),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('home-answer')));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationScreen), findsOneWidget);

      // A finalized visitor caption arrives.
      capturedRef.read(sessionControllerProvider.notifier).ingestCaption(
            const CaptionResult(
              speaker: CaptionSpeaker.visitor,
              text: 'can you take this package',
              isFinal: true,
              timestampMs: 0,
              confidence: 0.9,
            ),
          );
      await tester.pumpAndSettle();

      // The suggestion provider is now consulted (it was dead before, MED-13)
      // and its suggestions are pushed onto the reply controller, which the
      // reply bar reads (FR-7.1a against the fake Bedrock port). Asserted on the
      // controller because that is the single source the reply bar renders from.
      expect(bedrock.callCount, 1, reason: 'suggestion provider must be consulted');
      final reply = capturedRef.read(replyControllerProvider.notifier);
      expect(reply.contextualSuggestions, contains('Thanks, one moment'));
      expect(reply.contextualSuggestions, contains('Leave it there please'));
    });
  });

  group('Session start mode and refusal (MED-14)', () {
    testWidgets('a refused Privacy Mode request surfaces a notice and runs Clarity',
        (tester) async {
      final port = FakeSessionPort();
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          // Default provisioning: the on device model is NOT verified, so
          // Privacy Mode is refused.
          overrides: _overrides(session: port),
          child: MaterialApp(
            theme: ThresholdTheme.light(),
            home: Consumer(builder: (context, ref, _) {
              capturedRef = ref;
              return const HomeScreen();
            }),
          ),
        ),
      );
      await tester.pump();

      // Request Privacy Mode for the next session, then answer the door.
      capturedRef.read(settingsControllerProvider).requestModeChange(CaptionMode.privacy);
      await tester.tap(find.byKey(const ValueKey('home-answer')));
      await tester.pump();

      // The refusal is surfaced, not silent (MED-14).
      expect(find.byKey(const ValueKey('privacy-refused-notice')), findsOneWidget);
      await tester.pumpAndSettle();

      // The session runs in Clarity, not Privacy (plan.mode was used).
      expect(find.byType(ConversationScreen), findsOneWidget);
      expect(capturedRef.read(sessionControllerProvider.notifier).mode,
          SessionCaptionMode.clarity);
    });
  });

  group('First-run recording-consent gate (CRIT-06, FR-14.1, AT-14)', () {
    testWidgets('on first run answering shows the notice and blocks the session',
        (tester) async {
      final port = FakeSessionPort();
      await tester.pumpWidget(
        ProviderScope(
          // Not acknowledged: the gate must block live use.
          overrides: _overrides(session: port, consentAcknowledged: false),
          child: MaterialApp(theme: ThresholdTheme.light(), home: const HomeScreen()),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('home-answer')));
      await tester.pumpAndSettle();

      // The one-time notice is shown and the session was NOT started: the gate
      // blocks live use until acknowledged (FR-14.1). No session connect ran.
      expect(find.byType(RecordingNoticeScreen), findsOneWidget);
      expect(find.byType(ConversationScreen), findsNothing);
      expect(port.connectCalls, 0);
    });

    testWidgets('acknowledging the notice then unblocks the session',
        (tester) async {
      final port = FakeSessionPort();
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(session: port, consentAcknowledged: false),
          child: MaterialApp(theme: ThresholdTheme.light(), home: const HomeScreen()),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('home-answer')));
      await tester.pumpAndSettle();
      expect(find.byType(RecordingNoticeScreen), findsOneWidget);
      // The gate blocked the session: no connect yet.
      expect(port.connectCalls, 0);

      // Acknowledge the notice. The gate is now satisfied and the same answer
      // flow proceeds straight into the live session.
      await tester.tap(find.byKey(const ValueKey('recording-notice-ack')));
      await tester.pumpAndSettle();
      expect(find.byType(RecordingNoticeScreen), findsNothing);
      expect(find.byType(ConversationScreen), findsOneWidget);
      expect(port.connectCalls, 1);
    });

    testWidgets('a pre-acknowledged resident is never shown the notice',
        (tester) async {
      final port = FakeSessionPort();
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(session: port, consentAcknowledged: true),
          child: MaterialApp(theme: ThresholdTheme.light(), home: const HomeScreen()),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('home-answer')));
      await tester.pumpAndSettle();
      expect(find.byType(RecordingNoticeScreen), findsNothing);
      expect(find.byType(ConversationScreen), findsOneWidget);
    });
  });

  group('Home semantics (G4)', () {
    testWidgets('both actions keep their labels', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host());
      await tester.pump();
      expect(find.bySemanticsLabel('Answer the door'), findsOneWidget);
      expect(find.bySemanticsLabel('Open settings'), findsOneWidget);
      handle.dispose();
    });
  });

  group('Home copy (NFR-10)', () {
    test('no dashes in any home string', () {
      for (final copy in <String>[kHomeHeroSupportingLine, kHomeReadyExplanation]) {
        expect(copy.contains('\u2014'), isFalse);
        expect(copy.contains('\u2013'), isFalse);
      }
    });

    test('the orienting explanation is preserved verbatim from the old screen', () {
      // The redesign demoted this copy; it did not delete it.
      expect(
        kHomeReadyExplanation,
        'Ready. When someone is at your door you can answer with '
        'captions, and reply out loud when two way audio is available.',
      );
    });
  });
}
