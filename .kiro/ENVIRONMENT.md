# Build environment (sandbox)

Verified toolchain for building and testing Threshold in this workspace.

## Versions (installed and confirmed)

| Tool | Version | Manager | Status |
|---|---|---|---|
| Flutter | 3.38.10 (stable) | mise (global) | `flutter test` runs green |
| Dart | 3.10.9 | bundled with Flutter | working |
| Node.js | 20.20.2 (also 22, 24) | nvm | use 20 for backend |
| npm | 11.4.2 | nvm | working |

Flutter meets the spec floor (>= 3.24). Dart meets the floor (>= 3.4).

## Activation (run at the start of every shell)

```bash
# Flutter + Dart (via mise, installed globally)
export PATH="$(mise where flutter)/bin:$PATH"
export FLUTTER_GIT_URL="https://github.com/flutter/flutter.git"
export FLUTTER_SUPPRESS_ANALYTICS=true

# Node 20 (via nvm)
export NVM_DIR="/root/.nvm"; . "$NVM_DIR/nvm.sh" >/dev/null 2>&1; nvm use 20 >/dev/null 2>&1
```

## Known constraints in this sandbox

- Flutter prints a non-fatal "running as root" warning. It does not block `flutter test`,
  `flutter analyze`, `flutter pub get`, or compilation. It is cosmetic here.
- **No Android SDK / no emulator / no iOS toolchain.** Therefore:
  - `flutter test` (unit + widget tests): WORKS. This is the primary verification gate.
  - `flutter analyze`, `flutter pub get`, `dart format`: WORK.
  - `flutter build apk` / `flutter run` on a device or emulator: NOT AVAILABLE here. Device/emulator
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
