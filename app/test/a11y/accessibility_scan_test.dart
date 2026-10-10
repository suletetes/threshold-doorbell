// MED-46: an automated accessibility scan that runs in flutter test, so the
// HIGH-06 (tap action) and HIGH-07 (contrast) classes of defect cannot slip
// through again. Each primary screen is pumped and checked against Flutter's
// built-in accessibility guidelines:
//
//   * textContrastGuideline       : text meets the WCAG contrast minimums.
//   * androidTapTargetGuideline   : tap targets are at least 48x48.
//   * labeledTapTargetGuideline   : every tappable node has a label.
//
// The audit noted (MED-46) that R7 found zero uses of meetsGuideline anywhere;
// this is that missing gate. Design/AT-9 call for an a11y scan to gate the
// build, and the CI app job runs `flutter test`, so this runs there.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/app/home_screen.dart';
import 'package:threshold/app/providers.dart';
import 'package:threshold/consent/recording_notice.dart';
import 'package:threshold/consent/recording_notice_controller.dart';
import 'package:threshold/consent/recording_notice_screen.dart';
import 'package:threshold/design/theme.dart';
import 'package:threshold/reply/outbound_mode.dart';
import 'package:threshold/reply/reply_bar.dart';
import 'package:threshold/reply/reply_controller.dart';
import 'package:threshold/reply/reply_port.dart';
import 'package:threshold/reply/suggestion_provider.dart';
import 'package:threshold/session/captions_only_screen.dart';
import 'package:threshold/session/conversation_screen.dart';
import 'package:threshold/session/ring_app_launcher.dart';
import 'package:threshold/session/session_controller.dart';
import 'package:threshold/session/session_port.dart';
import 'package:threshold/settings/settings_controller.dart';
import 'package:threshold/settings/settings_screen.dart';

/// Run the three accessibility guidelines against the current frame. Shared by
/// every screen scan so a new screen gets the same gate for free.
Future<void> scanAccessibility(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
}

Future<SessionController> _liveController({bool probeSucceeds = true}) async {
  final c = SessionController(port: FakeSessionPort(probeSucceeds: probeSucceeds));
  await c.open(deviceId: 'front-door');
  return c;
}

void main() {
  group('Automated accessibility scan on every screen (MED-46, AT-9)', () {
    testWidgets('HomeScreen', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            sessionPortProvider.overrideWithValue(FakeSessionPort()),
            replyPortProvider.overrideWithValue(FakeReplyPort()),
            ringAppLauncherProvider.overrideWithValue(FakeRingAppLauncher()),
            bedrockSuggestionPortProvider.overrideWithValue(FakeBedrockSuggestionPort()),
            dataErasurePortProvider.overrideWithValue(FakeDataErasurePort()),
            consentStoreProvider.overrideWithValue(FakeConsentStore(acknowledged: true)),
          ],
          child: MaterialApp(theme: ThresholdTheme.light(), home: const HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await scanAccessibility(tester);
      handle.dispose();
    });

    testWidgets('SettingsScreen', (tester) async {
      final handle = tester.ensureSemantics();
      final c = SettingsController(erasure: FakeDataErasurePort());
      await tester.pumpWidget(
        MaterialApp(theme: ThresholdTheme.light(), home: SettingsScreen(controller: c)),
      );
      await tester.pumpAndSettle();
      await scanAccessibility(tester);
      handle.dispose();
    });

    testWidgets('RecordingNoticeScreen', (tester) async {
      final handle = tester.ensureSemantics();
      final c = RecordingNoticeController(FakeConsentStore());
      await c.load();
      await tester.pumpWidget(
        MaterialApp(theme: ThresholdTheme.light(), home: RecordingNoticeScreen(controller: c)),
      );
      await tester.pumpAndSettle();
      await scanAccessibility(tester);
      handle.dispose();
    });

    testWidgets('ConversationScreen (live, with reply bar)', (tester) async {
      final handle = tester.ensureSemantics();
      final controller = await _liveController();
      final reply = ReplyController(
        port: FakeReplyPort(),
        outbound: controller.outbound,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(
            controller: controller,
            replyBar: ReplyBar(controller: reply),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await scanAccessibility(tester);
      handle.dispose();
      controller.dispose();
    });

    testWidgets('CaptionsOnlyScreen (live)', (tester) async {
      final handle = tester.ensureSemantics();
      final controller = await _liveController(probeSucceeds: false);
      await tester.pumpWidget(
        MaterialApp(
          home: CaptionsOnlyScreen(
            controller: controller,
            launcher: FakeRingAppLauncher(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await scanAccessibility(tester);
      handle.dispose();
      controller.dispose();
    });

    testWidgets('ReplyBar in isolation', (tester) async {
      final handle = tester.ensureSemantics();
      final reply = ReplyController(
        port: FakeReplyPort(),
        outbound: OutboundModeMachine()..applyProbe(ProbeResult.success),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThresholdTheme.light(),
          home: Scaffold(
            body: ReplyBar(
              controller: reply,
              contextualSuggestions: const <String>['Thanks, one moment'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await scanAccessibility(tester);
      handle.dispose();
    });
  });
}
