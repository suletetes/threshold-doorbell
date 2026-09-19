# ProGuard / R8 keep rules for Threshold release builds.
#
# R8 (isMinifyEnabled) and resource shrinking (isShrinkResources) are enabled on
# the release buildType to cut the APK/AAB size. The native plugins below use
# reflection or are called from JNI, so R8 cannot see those references and would
# otherwise strip classes that are needed at runtime. These are the minimal keeps
# required for the release build to run; do not disable shrinking to avoid them.

# --- flutter_webrtc (org.webrtc): the Ring live-stream + outbound audio path ---
# The WebRTC native library resolves many Java classes from JNI by name.
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**
-keep class com.cloudwebrtc.webrtc.** { *; }
-dontwarn com.cloudwebrtc.webrtc.**

# --- Google ML Kit object detection (visual context, Task 19) ---
# ML Kit loads model and pipeline classes reflectively.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.internal.mlkit_**

# --- flutter_local_notifications (visitor alerts, FR-3.3) ---
# Notification receivers/serialization are referenced by the Android framework
# and via Gson, so keep the plugin classes and generic signatures.
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**
-keepattributes Signature
-keepattributes *Annotation*

# --- Gson (used internally by flutter_local_notifications) ---
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**

# --- flutter_tts (reply spoken aloud at the door) ---
-keep class com.tundralabs.fluttertts.** { *; }
-dontwarn com.tundralabs.fluttertts.**

# --- Flutter embedding: keep the deferred-components / Play Core stubs quiet ---
-dontwarn com.google.android.play.core.**
