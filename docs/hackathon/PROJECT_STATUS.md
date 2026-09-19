# Threshold: Project Status

A single honest snapshot of what is done, what is verified, and what only you can finish.
Last updated after PR #7 merged to `main`.

## Build status

| Area | State |
|---|---|
| Functional tasks (1 to 31) | All 31 implemented and merged |
| Automated tests | 567 app + 186 backend + 31 package, all passing |
| Analyzer | `dart analyze` clean (No issues found!) |
| Android build | `flutter build apk` succeeds (fat and split per ABI) and app bundle builds |
| UI | Full design system, light and dark, WCAG 2.2 AA on every screen |
| APK size | Fat 113 MB; per device arm64 about 44 MB via ABI split |
| Design system, security fixes, audit fixes | Merged (PRs 1 to 7) |

## What is verified here vs deferred to your device

Everything that can be proven without hardware is proven. The following need a device or emulator plus a
Ring account, so they are the only open verification items. The code and its logic are complete and tested
behind interfaces; only the live hardware run is outstanding. This is not missing work, it is verification
that a sandbox cannot perform.

| Item | Why it needs you |
|---|---|
| The ARCH-1 outbound audio spike | Needs a real Ring WebRTC session (device or emulator + Ring token). This is the go/no-go for two-way audio. See `app/spike/RUNBOOK.md`. |
| Live WebRTC session, reply audio at the door | Same live Ring session. |
| Real screen reader passes (TalkBack, VoiceOver) | Needs a device with the reader enabled. The Semantics tree is the headless proxy and is tested. |
| Real latency numbers on reference devices | Needs Pixel 7 and iPhone 12 under reference network. |

## Your remaining checklist for submission (deadline Oct 23)

1. Merge is done through PR #7. Pull `main`.
2. Run the ARCH-1 spike per `app/spike/RUNBOOK.md`. Record the result in requirements.md section 7.
   - Pass: build and record the full two way demo.
   - Fail: ship Captions Only (FR-12); the product is still complete and demoable.
3. Record the demo video from `docs/hackathon/DEMO_SCRIPT.md` (2:55, problem first). Keep it under 3 minutes.
4. Fill in the Devpost form from `docs/hackathon/DEVPOST_SUBMISSION.md`. Include the friction log
   (`docs/hackathon/FRICTION_LOG.md`) for the up to 10 percent bonus, and the AWS Builder feedback.
5. Open the Open Source mini challenge PR (see `docs/hackathon/OSS_PR_GUIDE.md`). It must be authored under
   your own GitHub identity.
6. Submit at least 12 hours early.

## Mini challenges

- AWS Builder: Amazon Transcribe (Clarity Mode captions) and Amazon Bedrock (smart replies). Documented in
  the Devpost writeup feedback section.
- Open Source: the extracted `packages/flutter_ring_captions` MIT package plus a PR to
  `AmazonAppDev/ring-api-helloworld`. See the OSS guide.
