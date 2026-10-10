# Build environment (sandbox)

Verified toolchain for building and testing Threshold in this workspace.

## Versions (installed and confirmed)

| Tool | Version | Manager | Status |
|---|---|---|---|
| Flutter | 3.38.10 (stable) | git clone at `/opt/flutter` | `flutter test` runs green |
| Dart | 3.10.9 | bundled with Flutter | working |
| Node.js | 20.20.2 (also 22, 24) | nvm | use 20 for backend |
| npm | 11.4.2 | nvm | working |
| Android SDK | platform-36, build-tools 36.0.0 | `/opt/android-sdk` | `flutter build apk` succeeds; no emulator (no KVM) |
| Java | 17 (OpenJDK) | mise `java@17.0.2` | used for the Android build |

Flutter meets the spec floor (>= 3.24). Dart meets the floor (>= 3.4).

## Activation (run at the start of every shell)

```bash
# Flutter + Dart (git clone at /opt/flutter) and the Android build toolchain
export PATH="/opt/flutter/bin:$(mise where java@17.0.2)/bin:/opt/android-sdk/platform-tools:$PATH"
export JAVA_HOME="$(mise where java@17.0.2)"
export ANDROID_HOME=/opt/android-sdk ANDROID_SDK_ROOT=/opt/android-sdk
export FLUTTER_GIT_URL="https://github.com/flutter/flutter.git"
export FLUTTER_SUPPRESS_ANALYTICS=true

# Node 20 (via nvm)
export NVM_DIR="/root/.nvm"; . "$NVM_DIR/nvm.sh" >/dev/null 2>&1; nvm use 20 >/dev/null 2>&1
```

## Known constraints in this sandbox

- Flutter prints a non-fatal "running as root" warning. It does not block `flutter test`,
  `flutter analyze`, `flutter pub get`, or compilation. It is cosmetic here.
- **Android SDK present; no emulator (no KVM); no iOS toolchain (no macOS, no `app/ios/` project).**
  Therefore:
  - `flutter test` (unit + widget tests): WORKS. This is the primary verification gate.
  - `flutter analyze`, `flutter pub get`, `dart format`: WORK.
  - `flutter build apk`: WORKS (the Android SDK at `/opt/android-sdk` is installed and licensed).
  - `flutter run` on a device or emulator: NOT AVAILABLE here (no KVM, so no emulator). On-device
    verification happens on the developer's machine.
  - Anything requiring a live Ring WebRTC session or a physical/simulated Ring device (task 2, the
    outbound-audio spike, and any integration that opens a real session): NOT AVAILABLE here; requires a
    Ring account, Ring Protection subscription, and a Playground/staging token obtained interactively by
    the developer.

## What this means for task execution

- Backend tasks (Node + Fastify) with fixture-based unit and contract tests: fully buildable and testable here.
- Flutter tasks whose logic is verifiable by `flutter test` (state machines, styling logic, widgets under
  the test harness, fixtures): fully buildable and testable here.
- Device-only and Ring-live tasks: implementable as code here, but final verification is deferred to the
  developer's machine with the Ring credentials. These are marked accordingly and never claimed "verified"
  from this sandbox.
