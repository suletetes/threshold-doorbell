# Building the Threshold Android APK

This guide walks you through building the Threshold resident app APK and
installing it on an Android phone (Phone B in the two-phone demo).

No prior Flutter knowledge is needed. Follow the steps in order.

---

## What you are building

Threshold is a two-way captioned doorbell app for deaf and hard of hearing
residents. The APK you build here runs on the resident's phone (Phone B). It:

- rings and vibrates when a visitor presses the doorbell,
- shows live captions of what the visitor says,
- lets the resident tap a reply that is spoken aloud at the door.

The app talks to a backend that is already deployed to AWS, so you do not need
to run any server. You only build and install the app.

---

## Prerequisites

Install these once on your computer (Windows, macOS, or Linux).

| Tool | Version | Check with | Get it |
|---|---|---|---|
| Flutter SDK | 3.24 or newer | `flutter --version` | https://docs.flutter.dev/get-started/install |
| Android toolchain | bundled with Flutter | `flutter doctor` | run `flutter doctor` and follow prompts |
| A phone or emulator | Android 8+ | `flutter devices` | USB cable or Android Studio emulator |

Run `flutter doctor` and make sure the Android section has a green check. If it
asks you to accept Android licenses, run:

```bash
flutter doctor --android-licenses
```

---

## Step 1. Get the code and dependencies

```bash
cd app
flutter pub get
```

This downloads the packages the app needs. It is safe to run again anytime.

---

## Step 2. Build the APK

The app is built in "demo" mode and pointed at the live AWS backend. Copy the
command for your shell exactly.

### Windows PowerShell

```powershell
cd app
flutter build apk --debug `
  --dart-define=DEMO=true `
  --dart-define=BACKEND_URL=https://threshold-demo.duckdns.org `
  --dart-define=DEVICE_ID=mock-doorbell-001
```

### macOS or Linux

```bash
cd app
flutter build apk --debug \
  --dart-define=DEMO=true \
  --dart-define=BACKEND_URL=https://threshold-demo.duckdns.org \
  --dart-define=DEVICE_ID=mock-doorbell-001
```

When it finishes you will see:

```
Built build/app/outputs/flutter-apk/app-debug.apk
```

That file is your APK.

> Note: you may see warnings about the Kotlin Gradle Plugin. They are warnings,
> not errors. The build still succeeds.

### What the three defines mean

| Define | Purpose |
|---|---|
| `DEMO=true` | Turns on the two-phone demo adapters (the app talks to the demo hub). |
| `BACKEND_URL` | The AWS backend address. The default already points at the live demo server. |
| `DEVICE_ID` | The room both phones share. Phone A must use the same id. Default is `mock-doorbell-001`. |

---

## Step 3. Install on a phone

### Option A. Phone connected by USB

1. On the phone, enable Developer Options: Settings, About phone, tap Build
   number seven times.
2. In Developer Options, turn on USB debugging.
3. Plug the phone into the computer and accept the "Allow USB debugging" prompt.
4. Install:

```bash
adb install build/app/outputs/flutter-apk/app-debug.apk
```

If an older copy is already installed, replace it with:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

### Option B. Copy the file to the phone

1. Copy `build/app/outputs/flutter-apk/app-debug.apk` to the phone (email,
   cloud drive, or USB file transfer).
2. On the phone, open the file and allow "install from this source" if asked.

---

## Step 4. Run the two-phone demo

1. On **Phone A** (the visitor), open Chrome and go to:
   `https://threshold-demo.duckdns.org/`
   Leave the Backend URL field empty. It loads with no certificate warning.
2. On **Phone B** (the resident), open the **Threshold** app you just installed.
3. The small debug chip at the bottom right of the app shows the connection
   state. Once Phone A is open it turns green ("hub+visitor").
4. On Phone A, tap **Ring**. Phone B alerts and opens the session.
5. Speak on Phone A. Captions appear on Phone B.
6. Tap a reply on Phone B. Phone A speaks it aloud.

Step 4 above is the full two-phone walkthrough, and the troubleshooting section
below covers the common snags.

---

## Running directly without installing (optional)

If the phone is connected by USB you can run the app straight from the computer,
which also streams logs to your terminal:

```bash
cd app
flutter devices          # find your phone id
flutter run --device-id=<your-phone-id> \
  --dart-define=DEMO=true \
  --dart-define=BACKEND_URL=https://threshold-demo.duckdns.org \
  --dart-define=DEVICE_ID=mock-doorbell-001
```

Every network step prints a line that starts with `[THRESHOLD]`, so you can
watch the ring, caption, and reply flow live.

---

## Building a release (signed) APK

The debug APK above is fine for the demo. A release APK needs a signing key.

1. Create an upload keystore (once):

```bash
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

2. Copy `app/android/key.properties.example` to `app/android/key.properties`
   and fill in the keystore path, passwords, and alias.
3. Build:

```bash
cd app
flutter build apk --release \
  --dart-define=DEMO=true \
  --dart-define=BACKEND_URL=https://threshold-demo.duckdns.org \
  --dart-define=DEVICE_ID=mock-doorbell-001
```

The release build fails on purpose if `key.properties` is missing, so a build
can never ship accidentally debug-signed.

Output: `build/app/outputs/flutter-apk/app-release.apk`.

---

## Troubleshooting

### `flutter: command not found`
Flutter is not on your PATH. Re-open the terminal after installing, or add the
Flutter `bin` folder to PATH.

### `flutter doctor` shows a red X on Android
Open Android Studio once to finish installing the Android SDK, then run
`flutter doctor --android-licenses` and accept all.

### The build says "No connected devices"
That only matters for `flutter run`. `flutter build apk` does not need a device.
Build the APK, then install it with `adb install`.

### The app shows "offline" on the debug chip
The phone cannot reach the backend. Confirm the phone has internet, then open
`https://threshold-demo.duckdns.org/ready` in the phone's browser. It should
show `{"ready":true}`. If it does not, the backend address may have changed; open
the debug panel in the app (tap the chip, bottom right) and update the Backend
URL field.

### Captions do not appear
Both phones must use the same Device ID. The default is `mock-doorbell-001` on
both sides. On Phone A, check the Device ID field in the Configuration section
matches the app's build.

### The phone blocks the install
Allow installs from the source you used (browser or file manager) in the
phone's settings, then open the APK again.

---

## Quick reference

```bash
# one time
cd app && flutter pub get

# build the demo APK
flutter build apk --debug \
  --dart-define=DEMO=true \
  --dart-define=BACKEND_URL=https://threshold-demo.duckdns.org \
  --dart-define=DEVICE_ID=mock-doorbell-001

# install
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Visitor page: `https://threshold-demo.duckdns.org/`
Two-phone walkthrough: Step 4 of this guide.
