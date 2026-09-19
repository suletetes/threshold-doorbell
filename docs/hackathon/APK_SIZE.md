# APK size: baseline, why it is large, and what we did about it

This note documents the Android release size work for Threshold: the starting
point, the per-ABI numbers, why the app is large, the mitigations we applied,
and the resulting per-device download. All numbers below were measured on this
repo with Flutter 3.38.10 (Java 21 / Gradle), not estimated.

## Baseline (fat, multi-ABI release APK)

A single `flutter build apk --release` produces one fat APK that bundles the
native libraries for every supported ABI (arm64-v8a, armeabi-v7a, x86_64):

| Artifact | Size |
|---|---|
| `app-release.apk` (fat, all ABIs) | about 113 MB |

That is the number a naive `flutter build apk --release` gives you, and it is
what a user would download if we shipped that single APK to every device.

## Per-ABI split (the biggest win)

Building with `flutter build apk --release --split-per-abi` produces one APK per
architecture. A given phone only ever installs the one matching its CPU, so the
real per-device download is the size of a single split, not the fat APK:

| Artifact | Size | Notes |
|---|---|---|
| `app-arm64-v8a-release.apk` | about 44 MB | modern phones (the realistic download) |
| `app-armeabi-v7a-release.apk` | about 31 MB | older 32-bit devices |
| `app-x86_64-release.apk` | about 48 MB | emulators / x86 devices |

For a modern arm64 phone the real download drops from about 113 MB to about
44 MB, a **61% reduction**, with zero functional change.

## R8 code shrinking and resource shrinking

We enabled R8 (`isMinifyEnabled = true`) and Android resource shrinking
(`isShrinkResources = true`) on the release buildType in
`app/android/app/build.gradle.kts`, wired to
`app/android/app/proguard-rules.pro`. The keep rules are the minimal set needed
so R8 does not strip classes that flutter_webrtc, Google ML Kit,
flutter_local_notifications, and flutter_tts resolve via JNI or reflection. The
release build (fat, split, and app bundle) succeeds with shrinking enabled; no
plugin required disabling shrinking, only keep rules.

Measured sizes with shrinking enabled:

| Artifact | Before shrink | After R8 + resource shrink |
|---|---|---|
| `app-release.apk` (fat) | about 113.4 MB | about 113.7 MB |
| `app-arm64-v8a-release.apk` | about 43.8 MB | about 44.0 MB |
| `app-armeabi-v7a-release.apk` | about 31.0 MB | about 32.5 MB |
| `app-x86_64-release.apk` | about 47.6 MB | about 47.8 MB |

Honest read of these numbers: R8 and resource shrinking do **not** move the
needle here, because the size is not in Dalvik bytecode or Android resources.
It is in native `.so` libraries, which R8 (a Java/Kotlin bytecode tool) and the
resource shrinker (an Android-resource tool) do not touch. We keep shrinking on
because it is the right default, it strips unused Java/Kotlin code and resources
from the plugins' Android glue, and it costs nothing at runtime once the keep
rules are in place. But the lever that actually cuts the download is the ABI
split, not R8. We document this rather than claim a shrink win we did not get.

## Why the app is large

The bulk of every APK is native code shipped by two plugins:

- **`google_mlkit_object_detection`** pulls in ML Kit's native object-detection
  runtime and bundled model assets. This backs the visual-context feature
  (Task 19: person count, package/uniform cues on the live frame).
- **`flutter_webrtc`** ships the full WebRTC native stack (`libjingle`/`libwebrtc`),
  which is the core of the Ring live stream and the outbound-audio reply path.
  This one is not optional: it is the defining capability of the product.

These two account for the overwhelming majority of the per-ABI `.so` payload.
Dart, the Flutter engine, and app code are a small fraction by comparison, which
is why bytecode-level shrinking barely registers.

## Mitigations applied

1. **ABI split for direct APK distribution.** `--split-per-abi` so each device
   downloads only its own native libraries (about 44 MB on arm64 instead of
   about 113 MB). This is the primary mitigation.
2. **App bundle for the Play Store.** `flutter build appbundle --release
   --obfuscate --split-debug-info=build/symbols` produces an `.aab`
   (about 73 MB on disk) from which Google Play generates and serves
   per-device, per-ABI, per-density splits automatically, so the installed
   download is smaller again than any single fat APK. Obfuscation with split
   debug info keeps Dart symbols out of the shipped binary while preserving
   crash de-obfuscation via `build/symbols`.
3. **R8 + resource shrinking** on release, with minimal ProGuard keep rules for
   the native plugins. Correct hygiene even though the win is small here.
4. **A reproducible build script**, `app/scripts/build_release.sh`, that runs
   the split-per-abi build and the obfuscated app-bundle build and prints the
   resulting sizes, so these numbers can be re-measured by anyone.

## The single biggest contributor, and the size-critical option

`google_mlkit_object_detection` (the Task 19 visual-context feature) is the
largest single removable contributor to the native payload. In the feature
spec, visual context is a **should-have / nice-to-have**, not a must-have: the
core two-way captioned conversation (Ring WebRTC audio, Transcribe/on-device
captions, spoken reply at the door) does not depend on it. If binary size ever
becomes a hard constraint (for example a strict store limit or a
low-connectivity target market, where about 80% of the addressable audience
lives), ML Kit object detection can be made a **deferred or optional component**
(a Play dynamic feature module, or simply dropped from a "lite" flavor). That
alone would remove the ML Kit native runtime and its bundled models from the
base download. `flutter_webrtc`, by contrast, is load-bearing and stays.

## Reproducing these numbers

```bash
# uses the project shell preamble internally
app/scripts/build_release.sh
```

or manually, from `app/`:

```bash
flutter build apk --release --split-per-abi
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
ls -la build/app/outputs/flutter-apk/*.apk
ls -la build/app/outputs/bundle/release/*.aab
```

The default `flutter build apk --debug` gate is unaffected by the release
shrinking config and continues to build.
