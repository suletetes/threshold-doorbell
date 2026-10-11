# ProGuard / R8 keep rules for Threshold release builds.
#
# R8 (isMinifyEnabled) and resource shrinking (isShrinkResources) are enabled on
# the release buildType. Each library ships its own consumer ProGuard rules, which
# R8 applies automatically, so we add as few project rules as possible (MED-19).
#
# The broad `-keep class <pkg>.** { *; }` blanket rules that previously covered
# flutter_webrtc, Google ML Kit, flutter_local_notifications and flutter_tts were
# removed: those plugins are no longer dependencies (HIGH-01), and blanket keeps
# defeat shrinking and hide missing-class errors. When any of those adapters is
# re-added, prefer its documented consumer rules and add only the narrow keep its
# README requires.
#
# No project-specific keep rules are needed for the current dependency set
# (flutter_riverpod, shared_preferences). Flutter's own embedding rules are applied
# by the Flutter Gradle plugin. Add narrow rules here only when a release smoke test
# surfaces a concrete missing class.
