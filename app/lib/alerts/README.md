# alerts/

The doorbell for someone who cannot hear it.

- **Haptic vocabulary:** distinct, distinguishable vibration patterns per event
  (person-at-door vs motion vs conversation-started) via `vibration`. A deaf user must tell events apart
  without looking.
- **Visual alert:** full-bleed visitor thumbnail from the webhook `thumbnail_url`; optional photosensitivity-safe
  screen flash as a software replacement for the flashing-light hardware this market sells.
- **Notifications:** `flutter_local_notifications`; wearable relay for wrist haptics (nice-to-have).
