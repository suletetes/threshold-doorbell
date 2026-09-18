# Hackathon Win Strategy — Threshold (threshold-doorbell)

*Ruthless stick-or-change evaluation. Amazon Developer Hackathon 2026 · Ring track · Flutter.
Prepared with caveman-density analysis; rendered as prose because it is a document for humans.*

---

## 1. Executive recommendation

**STICK — but understand you are at the starting line, not the finish, and the one thing that makes
Threshold special is the one thing you have not proven.**

**Confidence: 72%** that sticking beats switching. Not higher, because of one hard, specific risk (below).
Not lower, because the idea itself is genuinely elite and the alternatives are weaker.

The blunt version: **the concept is a likely winner; the current project is a pile of excellent documents
and zero working code.** Those are not the same thing. Judges score what runs on screen, not what is
written in a spec. Right now you would score near zero on execution, completeness, and demo — because none
exist yet. The good news: you have ~38 days, which is generous. The decision is not "is the idea good"
(it is), it is "can you de-risk the outbound-audio problem fast enough to build the demo that wins." Do the
spike this week and the answer is very likely yes.

---

## 2. Current project autopsy

**What actually exists (verified by reading the repo):**
- `app/lib/main.dart` — 54 lines, a placeholder home screen. Does nothing.
- `app/lib/reply/audio_spike.dart` — 38 lines, throws `UnimplementedError`. The critical experiment is not run.
- README files in each `lib/` folder describing intent. No logic.
- `pubspec.yaml` with dependencies declared but not installed (Flutter is not even in the build env here).
- Five strong strategy/spec/research docs.

**Total functional code: ~0 lines.** This is a documentation project wearing a Flutter skeleton.

### Honest scores (today, as-is)

| Criterion | Score | Evidence |
|---|---|---|
| Innovation / Originality | **9/10** | Two-way captioned doorbell is uncontested; no competitor found across many searches. |
| Technical Execution & Difficulty | **1/10** | Nothing is built. The hard part (outbound audio) is unproven and the obvious library path is blocked (see §3). |
| Real-world Impact & Usefulness | **9/10** | WHO: 430–466M with disabling hearing loss; captioning is a recognized aid. |
| Design / UX / Polish | **1/10** | One placeholder screen. |
| Demo Effectiveness | **1/10 now → 9/10 potential** | The *potential* demo (a deaf person converses at their door) is best-in-class. It does not exist yet. |
| Completeness | **1/10** | Skeleton only. |
| **Overall win probability, TODAY** | **~5%** | Because nothing runs. |
| **Overall win probability, IF the demo ships** | **~55–65%** | Elite idea + strong track fit + huge impact story. |

The gap between 5% and 60% is entirely execution. That gap is the whole game.

### Strengths (real, defensible)
- Uncontested white space; a "why has nobody done this" idea.
- Emotional, visceral, instantly-legible demo *if* built.
- Idiomatic use of the sponsor stack (Ring `sendrecv` audio, `person_detected` events — verified in source).
- Massive, well-documented, sympathetic audience → top marks on Potential Impact.
- Strategy work already done: you know exactly what to build and why.

### Weaknesses (brutal)
- **Zero working code with ~38 days left.** Not fatal, but you are behind where the docs imply.
- **The differentiator is the unproven part.** Captions are easy; the *reply out of the doorbell* is the
  novelty, and it is the riskiest component (§3).
- **Over-invested in planning, under-invested in a spike.** Eight commits, all docs. The one commit that
  matters — a working audio spike — does not exist.
- Depends on external gating (Ring account, Protection subscription, staging users) not yet set up.

---

## 3. Competitive, technical & trend findings

### 3.1 The competitor that matters: Google Live Transcribe
Free, **500M+ downloads**, 80+ languages, offline since 2022, built with Gallaudet University. It is what
deaf users already use. **It is one-way and doorbell-blind** — it captions the room, cannot answer a door,
has no visitor context. **Implication:** if you pitch Threshold as "captions for your door," you lose to a
free 500M-download incumbent. If you pitch it as **two-way conversation at the door**, you are uncontested.
This single positioning choice materially moves your win probability.

### 3.2 The technical risk got WORSE on closer inspection
- **flutter_webrtc's capability matrix shows "Insertable Streams" unsupported on every platform**
  (verified on pub.dev and the repo README). Insertable Streams is the clean way to inject synthesized
  audio into an outbound track. It is not available.
- **`flutter_tts` can `synthesizeToFile`** (produces a WAV/PCM buffer) — so generating the voice is solved —
  **but it has no hook into a WebRTC peer connection.** It only plays to the device speaker.
- **Net:** the "push TTS into the outbound track" path is harder than the spec assumed. The **WebView audio
  pipeline** (browser WebRTC + `AudioContext` → `MediaStreamTrack`) is likely the *real* path, not a
  fallback. Confidence: High that this is the crux; Medium on which exact approach lands.

### 3.3 What wins device/product-adoption hackathons (2025–2026 patterns)
- A single, legible, emotional demo beats broad feature lists.
- Deep, idiomatic use of the sponsor's own capabilities scores the Tech axis (Threshold does this).
- Accessibility + AI is a judge-favored theme and a genuine differentiator.
- Working-but-narrow beats ambitious-but-broken. Every time.

### 3.4 Direct competitor search result
No captioning+reply doorbell found anywhere (triangulated across product sites, app framing, and search;
some endpoints blocked, so not absolute). The white space is real.

---

## 4. Win probability assessment

| Scenario | Win probability | Trigger |
|---|---|---|
| Do nothing / keep writing docs | ~5% | Status quo |
| Ship captions-only (no outbound audio) | ~35–45% | R1 spike fails, degrade gracefully |
| Ship full two-way demo | ~55–65% | R1 spike succeeds (likely via WebView) |
| Switch to ClaimDebate now | ~30% | Abstract demo, narrow B2B, but buildable |
| Switch to FormCoach | ~0% | Dead — Fire TV exposes no camera/ML API (verified) |

**The expected value of sticking dominates every alternative — conditional on running the spike now.**

---

## 5. High-leverage improvements (STICK plan)

Ranked by leverage. Do them in this order.

1. **Run the R1 audio spike THIS WEEK, WebView-first.** Prove a synthesized voice reaches the doorbell over
   Ring's WebRTC session inside a WebView. This is the single highest-leverage action in the entire project.
   Nothing else matters until this is answered. Timebox: 3 days. Go/no-go.
2. **Define and lock the "captions-only" graceful degrade** as an explicit, still-winning scope. If R1 fails
   on day 3, you pivot to Threshold-minus-outbound-audio — still novel, still demoable, still beats Live
   Transcribe on doorbell context. This converts your fatal risk into a feature-level risk.
3. **Reposition everything around "two-way, not captions."** One sentence in the demo dismissing Live
   Transcribe ("great for the room you're in — it can't answer your door"). Costs nothing, adds credibility.
4. **Set up Ring access now** (account, OAuth app, Protection subscription, Playground token, staging user).
   External gating should never be on the critical path late.
5. **Build the skeleton end-to-end ugly by ~day 10** (25% mark): webhook → alert → live view → caption on
   screen → one canned reply. Ugly on purpose. Something to improve, not to finish.
6. **Bank the free points:** friction log (up to 10% judging bonus), both mini-challenges (AWS Builder via
   Transcribe+Bedrock; Open Source via `flutter_ring_captions` + a PR to Amazon's sample), visible MIT
   license (already done).
7. **Rehearse the demo 5×, record twice, submit 12h early.** The last four hours are a separate project.

---

## 6. Stronger alternatives (only if the R1 spike fails outright)

There is **no full idea switch that beats Threshold** — the alternatives were already scored lower and one
is dead. So the "change" options are really *scope changes within Threshold*, not new projects:

- **Option A (recommended fallback): Threshold captions-only.** Drop outbound audio. Live captions of the
  visitor + a visitor-facing on-screen prompt / QR / tap flow so the resident can still communicate. Still
  Ring track, still novel, ~35–45% win. This is the pivot, and it is a small one.
- **Option B (last resort): ClaimDebate (Alexa+).** Only if you decide Ring hardware access is a blocker you
  cannot clear. Citations verified (arXiv:2606.18021 real; Stanford 58–88% real), architecture clever, but
  the demo is abstract and B2B-narrow. ~30% win. Do not switch to this unless Threshold is truly blocked.
- **Do NOT consider FormCoach.** Fire TV exposes no camera or ML API to apps (verified: zero hits across all
  official sample repos). It cannot be built.

---

## 7. Exact next actions (prioritized)

1. **Today:** create the Ring developer account, OAuth app, request the Playground token; add a Ring
   Protection plan + one staging user. (Unblocks everything; not on the coding critical path.)
2. **Days 1–3:** the WebView-first R1 audio spike. Prove voice out of the doorbell. **Go/no-go gate.**
3. **Day 3 decision:** spike passes → full two-way build. Spike fails → lock captions-only scope (Option A).
4. **Days 4–10:** ugly end-to-end skeleton (webhook → alert → live view → caption → one reply).
5. **Days 11–22:** Transcribe captions, Bedrock smart replies, haptic vocabulary, transcript history.
6. **Days 23–30:** accessibility pass (WCAG 2.2 AA), polish, onboarding, error states.
7. **Days 31–36:** feature freeze, demo rehearsal ×5, record video ×2, friction log, product feedback,
   OSS package + PR.
8. **Day 37–38:** code lock, submit 12h early.

**The one action that changes your odds the most: the spike, this week. Everything else is downstream.**

---

## 8. Sources

- Repo state: direct read of `app/` and `git log` (no functional code; docs only).
- flutter_webrtc capability matrix — pub.dev/packages/flutter_webrtc and repo README (Insertable Streams
  unsupported all platforms).
- flutter_tts — pub.dev/packages/flutter_tts (`synthesizeToFile` yes; no WebRTC hook).
- Google Live Transcribe — Wikipedia/Google (500M+ downloads, 80+ languages, offline 2022, Gallaudet, Apache 2.0).
- WHO — deafness and hearing loss (430–466M disabling; captioning as recognized aid).
- Ring developer docs + `ring-api-helloworld` source — `sendrecv` audio, `person_detected` events,
  100 req/s, Protection-plan test requirement, mandatory watermark.
- arXiv:2401.01301 (Stanford, 58–88% legal hallucination) and arXiv:2606.18021 (ICML 2026) — for the
  ClaimDebate alternative's evidentiary basis.
- Prior project docs: `AGGRESSIVE_RESEARCH_REPORT.md`, `research-and-scoring.md`, `threshold-spec.md`.

---

*Bottom line: the idea is a winner; the project is unbuilt. Stick, run the spike this week, and turn the
one fatal risk into a feature-level risk with a captions-only fallback. Do that and you are a genuine
contender. Keep writing docs instead and you will lose to someone who shipped something ugly that ran.*
