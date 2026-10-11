#!/usr/bin/env bash
#
# build_release.sh - reproducible, size-optimised release builds for Threshold.
#
# Produces:
#   1. Per-ABI release APKs (--split-per-abi) so each device downloads only its
#      own native libraries instead of the fat multi-ABI APK.
#   2. An obfuscated Android App Bundle (.aab) for the Play Store, with the
#      Dart debug symbols split out to build/symbols for later crash
#      de-obfuscation.
# Then it prints the resulting file sizes.
#
# R8 code shrinking and resource shrinking are enabled on the release buildType
# in android/app/build.gradle.kts; the ProGuard keep rules live in
# android/app/proguard-rules.pro. See docs/hackathon/APK_SIZE.md for the
# measured baseline and after-shrink numbers.
#
# Usage (from anywhere):
#   app/scripts/build_release.sh
#
set -euo pipefail

# --- Environment. Respect anything the caller already exported, and otherwise
#     discover tools rather than hard-coding paths. The project pins Java 17
#     (see .kiro/ENVIRONMENT.md); mise is optional. ---

# Java: prefer an exported JAVA_HOME, else ask mise for Java 17 if available.
if [ -z "${JAVA_HOME:-}" ] && command -v mise >/dev/null 2>&1; then
  if mise where java@17.0.2 >/dev/null 2>&1; then
    JAVA_HOME="$(mise where java@17.0.2)"
  elif mise where java@17 >/dev/null 2>&1; then
    JAVA_HOME="$(mise where java@17)"
  fi
fi

# Flutter: prefer a flutter already on PATH; else ask mise for the pinned
# version if it is installed. Never fail just because mise lacks it.
FLUTTER_BIN_DIR=""
if ! command -v flutter >/dev/null 2>&1 && command -v mise >/dev/null 2>&1; then
  if mise where flutter@3.38.10 >/dev/null 2>&1; then
    FLUTTER_BIN_DIR="$(mise where flutter@3.38.10)/bin"
  fi
fi

# Android SDK: derive from ANDROID_HOME / ANDROID_SDK_ROOT if either is set;
# keep them in sync. Do not invent a default path (the old /projects/android-sdk
# default did not exist here); if neither is set the Gradle build reports the
# missing SDK with its own clear message.
if [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -z "${ANDROID_HOME:-}" ]; then
  ANDROID_HOME="${ANDROID_SDK_ROOT}"
elif [ -n "${ANDROID_HOME:-}" ] && [ -z "${ANDROID_SDK_ROOT:-}" ]; then
  ANDROID_SDK_ROOT="${ANDROID_HOME}"
fi

export JAVA_HOME
[ -n "${ANDROID_HOME:-}" ] && export ANDROID_HOME
[ -n "${ANDROID_SDK_ROOT:-}" ] && export ANDROID_SDK_ROOT
export PATH="${JAVA_HOME:+$JAVA_HOME/bin:}${FLUTTER_BIN_DIR:+$FLUTTER_BIN_DIR:}${ANDROID_SDK_ROOT:+$ANDROID_SDK_ROOT/platform-tools:}$PATH"
export FLUTTER_SUPPRESS_ANALYTICS=true
ulimit -n 65536 || true

# --- Locate the app directory (the parent of this script's directory). ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${APP_DIR}"

echo "==> Building size-optimised release artifacts for Threshold"
echo "    app dir: ${APP_DIR}"
echo

# --- 1. Per-ABI release APKs. Splitting by ABI is the single biggest win: a
#     modern arm64 phone downloads only its own native libraries. ---
echo "==> flutter build apk --release --split-per-abi"
flutter build apk --release --split-per-abi

# --- 2. Obfuscated app bundle for the Play Store, with split debug symbols. ---
echo
echo "==> flutter build appbundle --release --obfuscate --split-debug-info=build/symbols"
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols

# --- 3. Report sizes. ---
APK_DIR="build/app/outputs/flutter-apk"
AAB_DIR="build/app/outputs/bundle/release"

echo
echo "==> Resulting artifact sizes"
if [ -d "${APK_DIR}" ]; then
  for apk in "${APK_DIR}"/*-release.apk; do
    [ -e "${apk}" ] || continue
    printf '    %-40s %s\n' "$(basename "${apk}")" "$(du -h "${apk}" | cut -f1)"
  done
fi
if [ -d "${AAB_DIR}" ]; then
  for aab in "${AAB_DIR}"/*.aab; do
    [ -e "${aab}" ] || continue
    printf '    %-40s %s\n' "$(basename "${aab}")" "$(du -h "${aab}" | cut -f1)"
  done
fi

echo
echo "==> Done. Per-ABI APKs are in ${APK_DIR}; the app bundle is in ${AAB_DIR}."
echo "    Dart debug symbols (for crash de-obfuscation) are in build/symbols."
