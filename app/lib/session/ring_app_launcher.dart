// Ring app launcher port (Task 17, FR-12.3; AT-6, AT-10). In Captions-Only Mode
// the resident is offered a one-tap action to open the official Ring app for
// two-way talk, so a hearing household member (or the resident's own chosen
// method) can respond (FR-12.3). The app never claims to send audio itself in
// this mode. Launching another app is a platform action (url_launcher /
// platform channel) that is device-bound, so it sits behind this interface with
// a fake for headless widget tests.

import 'dart:async';

/// Launches the official Ring app (FR-12.3). The live binding opens the Ring app
/// via its deep link / store fallback; the fake records the attempt.
abstract class RingAppLauncher {
  /// Attempt to open the Ring app. Returns true if it could be launched.
  Future<bool> openRingApp();
}

/// Deterministic fake for tests. Records launch attempts and can simulate an
/// app-not-installed outcome.
class FakeRingAppLauncher implements RingAppLauncher {
  FakeRingAppLauncher({this.canLaunch = true});

  final bool canLaunch;
  int launchCalls = 0;

  @override
  Future<bool> openRingApp() async {
    launchCalls++;
    return canLaunch;
  }
}
