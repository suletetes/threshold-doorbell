# APK size: baseline, why it was large, and what we did about it

This note documents the Android size work for Threshold: the starting point, why
the app was large, the fix we actually applied, and the resulting download. All
numbers below were measured on this repo with Flutter 3.38.10 (Java 17 / Gradle),
not estimated.

## Baseline (before the fix)

A debug fat APK that bundled the native libraries for every supported ABI
(arm64-v8a, armeabi-v7a, x86_64) measured:

| Artifact | Size |
|---|---|
| `app-debug.apk` (fat, all ABIs) | about 210 MB (219,343,297 bytes) |

The overwhelming majority of that payload was native `.so` code from plugins
that nothing in the app actually imported.

## Why the app was large

Two plugins shipped tens of MB of native code each, across three ABIs, for
features that are not implemented and that no Dart code references:

- **`flutter_webrtc`** shipped the full WebRTC native stack
  (`libjingle_peerconnection_so.so`). The architecture decision in `design.md`
  §2 is that the Ring live stream runs through `webview_flutter` and browser
  WebRTC, **not** through `flutter_webrtc`, so this plugin was dead weight.
- **`google_mlkit_object_detection`** shipped ML Kit's native object-detection
  runtime (`libmlkitcommonpipeline.so`) plus bundled models, and silently
  pulled in legacy Firebase Instance ID and Google telemetry (the `WAKE_LOCK`
  and `c2dm.RECEIVE` permissions and an exported `FirebaseInstanceIdReceiver`;
  see MED-17). There is no object-detection feature in the spec.

Together these two accounted for about 60 MB of native libraries across the
three ABIs. A grep confirmed zero Dart imports of either plugin (HIGH-01).

## The fix we actually applied

The real fix was **removing the unused plugins**, not splitting the APK. We
removed `flutter_webrtc`, `google_mlkit_object_detection`, `flutter_tts`,
`vibration`, `http`, `web_socket_channel`, and `flutter_local_notifications`
from `app/pubspec.yaml`, keeping only what the app imports today
(`flutter_riverpod`, `shared_preferences`, `collection`). Each removed plugin is
listed as a commented placeholder in `pubspec.yaml` so it can be added back when
its real adapter is wired.

Measured debug fat APK after removal:

| Artifact | Before | After | Change |
|---|---|---|---|
| `app-debug.apk` (fat, all ABIs) | about 210 MB | about 140 MB (146,769,908 bytes) | about 70 MB smaller |

The `libjingle_peerconnection_so.so` and `libmlkitcommonpipeline.so` native
libraries are gone from the APK (`unzip -l app-debug.apk | grep -E 'libjingle|libmlkit'`
returns nothing), and the Firebase IID `WAKE_LOCK` / `c2dm.RECEIVE` permissions
no longer appear in `aapt dump permissions`.

## R8 and resource shrinking

R8 (`isMinifyEnabled = true`) and resource shrinking (`isShrinkResources = true`)
remain enabled on the release buildType in `app/android/app/build.gradle.kts`.
They are correct hygiene, but they never moved the needle on size here: the size
was in native `.so` libraries, which a Java/Kotlin bytecode tool and the Android
resource shrinker do not touch. The lever that cut the download was removing the
plugins. The keep rules in `proguard-rules.pro` were narrowed to match the
plugins that remain (MED-19).

## Per-ABI split (secondary, for a real device build)

A per-device download can be reduced further with per-ABI splits, so a phone
installs only its own native libraries. Note that a plain
`flutter build apk --release` still produces a single fat APK: the split is
**not** wired into Gradle (there is no `splits { abi { } }` block), so only the
`app/scripts/build_release.sh` path, which passes `--split-per-abi`, produces
split APKs today (NIT-14). Treat `build_release.sh` as the supported release
path, or add a `splits` block if plain `flutter build apk` must split.

## Reproducing these numbers

From `app/`:

```bash
flutter build apk --debug
ls -la build/app/outputs/flutter-apk/app-debug.apk
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep -E 'libjingle|libmlkit'   # expect no output
aapt dump permissions build/app/outputs/flutter-apk/app-debug.apk | grep -E 'RECORD_AUDIO|INTERNET'
```
