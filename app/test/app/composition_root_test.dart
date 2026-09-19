// P2-1: the composition root builds a real running product. This pumps the root
// app inside a ProviderScope with the device/Ring/network ports overridden by
// the existing fakes, and asserts it builds and navigates to the live session
// (Conversation or Captions-Only) and to Settings without throwing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/app/home_screen.dart';
import 'package:threshold/app/providers.dart';
import 'package:threshold/main.dart';
import 'package:threshold/reply/reply_port.dart';
import 'package:threshold/reply/suggestion_provider.dart';
import 'package:threshold/session/captions_only_screen.dart';
import 'package:threshold/session/conversation_screen.dart';
import 'package:threshold/session/ring_app_launcher.dart';
import 'package:threshold/session/session_port.dart';
import 'package:threshold/settings/settings_controller.dart';

List<Override> _fakeDeviceOverrides({bool probeSucceeds = true}) {
  return <Override>[
    sessionPortProvider.overrideWithValue(FakeSessionPort(probeSucceeds: probeSucceeds)),
    replyPortProvider.overrideWithValue(FakeReplyPort()),
    ringAppLauncherProvider.overrideWithValue(FakeRingAppLauncher()),
    bedrockSuggestionPortProvider.overrideWithValue(FakeBedrockSuggestionPort()),
    dataErasurePortProvider.overrideWithValue(FakeDataErasurePort()),
  ];
}

void main() {
  group('Composition root (P2-1)', () {
    testWidgets('the root app builds without throwing', (tester) async {
      await tester.pumpWidget(
        ProviderScope(overrides: _fakeDeviceOverrides(), child: const ThresholdApp()),
      );
      await tester.pump();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('home-answer')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-settings')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('answering the door navigates to the two-way Conversation screen', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _fakeDeviceOverrides(probeSucceeds: true),
          child: const ThresholdApp(),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('home-answer')));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed probe routes to the Captions-Only screen', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _fakeDeviceOverrides(probeSucceeds: false),
          child: const ThresholdApp(),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('home-answer')));
      await tester.pumpAndSettle();
      expect(find.byType(CaptionsOnlyScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opening settings navigates to the Settings screen', (tester) async {
      await tester.pumpWidget(
        ProviderScope(overrides: _fakeDeviceOverrides(), child: const ThresholdApp()),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('home-settings')));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
