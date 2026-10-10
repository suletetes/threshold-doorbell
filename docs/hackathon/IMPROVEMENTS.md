# Threshold — Prioritized Improvements

> **Historical and superseded (as of 2026-10-10).** This is an early strategy document and no longer
> reflects the current plan. The authoritative source of truth is `.kiro/specs/threshold-doorbell/`.
> In particular, the Tier 1.2 "visitor-facing on-screen/tap flow" fallback below was ruled out by
> `tasks.md` task 17 (N9, no visitor-facing prompt). Read this for context only.

*What actually moves win probability, ranked by leverage — not by how impressive it sounds. Amazon
Developer Hackathon 2026 · Ring track · Flutter.*

**The one-line version:** the biggest improvement to Threshold is not a feature — it is proving the
outbound-audio spike works, this week. Everything in Tier 2 and Tier 3 multiplies a demo that exists.
None of it matters if the core cannot run.

Sequence: **spike → fallback plan → repositioning → emotional demo → free points.**

---

## Tier 1 — moves you from ~60% → ~85% win probability (do these or you likely lose)

### 1. Prove the outbound audio spike (WebView-first)
This is the whole ballgame. The differentiator is "the doorbell talks back," and it is the one unproven —
and now harder — part: `flutter_webrtc` lists **Insertable Streams as unsupported on every platform**
(verified on pub.dev + repo), and `flutter_tts` can render a voice file but has **no hook into a WebRTC peer
connection**. Until a synthesized voice provably reaches the doorbell, the project is at ~5% regardless of
how good the docs are.
- **Action:** WebView-first spike (browser WebRTC + `AudioContext` → `MediaStreamTrack`), 3-day timebox,
  go/no-go gate.
- **Why it wins:** it is the foundation everything else is polish on.

### 2. Define a captions-only fallback scope *in advance*
If the spike fails on day 3, you must already know exactly what ships instead: live captions of the visitor
plus a visitor-facing on-screen/tap flow — still Ring track, still novel, still beats the incumbent on
doorbell context. This converts a **fatal** risk into a **feature-level** risk.
- **Action:** write the degrade scope now, before the spike, so a failure triggers a plan, not a panic.
- **Why it wins:** winning teams always have the degrade path pre-decided.

### 3. Reposition the entire pitch to "two-way, not captions"
Zero engineering cost, large effect. Google Live Transcribe is free, has 500M+ downloads, is offline, and
was built with Gallaudet University — but it is **one-way and doorbell-blind**. If you pitch "captions for
your door," you lose to it. If you pitch **two-way conversation at the door**, you are uncontested.
- **Action:** one sentence in the demo that dismisses it — "great for the room you're in; it can't answer
  your door."
- **Why it wins:** it is the difference between "nice accessibility app" and "why has nobody done this."

---

## Tier 2 — the difference between "works" and "wins the demo"

### 4. An emotional 15-second open
Lead with a real named persona (Priya) missing a real interaction, before any technology appears. Judges
score the *problem* harder than the solution; losing teams spend ~5% of the demo on the problem, winners
~30%.
- **Why it wins:** it makes judges *feel* the gap in the first 15 seconds.

### 5. The haptic vocabulary as a visible wow moment
Distinct vibration patterns (person-at-door vs motion vs conversation-started) are not a footnote. Demoed
well — the phone buzzes *differently* on camera — it shows you understand deaf users experience the world
differently, not just "we added captions."
- **Why it wins:** it is a cheap, tangible signal of deaf-first design depth.

### 6. Confidence-styled captions
Render low-confidence words as visibly uncertain. A small UI detail that signals product maturity and
safety-awareness: never present a guess as fact at someone's front door.
- **Why it wins:** judges notice restraint and safety thinking; it reads as a real product, not a hack.

---

## Tier 3 — free points most teams leave on the table

### 7. The friction log — up to a 10% judging bonus
Explicitly stated in the rules. In a close contest this alone can decide it. Nearly free if you log
continuously during the build instead of reconstructing it at the end.
- **Action:** keep a running friction log from day 1 (task attempted, expected vs actual, severity,
  workaround, suggestion).

### 8. Both mini-challenges
- **AWS Builder:** Amazon Transcribe (captions) + Bedrock (smart replies) — services you are using anyway.
- **Open Source:** publish `flutter_ring_captions` as an MIT package **and** open a PR to
  `AmazonAppDev/ring-api-helloworld` (their CONTRIBUTING welcomes PRs). A PR to the sponsor's own sample is
  maximally visible to judges.
- **Why it wins:** two extra shots at a prize for marginal effort.

### 9. WCAG 2.2 AA — met, and stated out loud
Ring's own partner UX guide mandates it. Meeting it and naming it in the demo maps straight to the Design
criterion and proves ecosystem understanding (a stated judging axis).

---

## What would NOT improve it (resist these)

- **More features** (translation, sign-language, Fire TV companion) — scope creep; they dilute the one
  legible demo.
- **More documentation** — you already have more than enough; the next doc has near-zero marginal value.
- **Multi-agent / chatbot layers** — pushes toward the "AI wrapper" trap you correctly avoided.
- **Polishing screens before the spike passes** — you could polish a UI for a product that cannot exist.

---

## Priority order (do in this sequence)

1. Set up Ring access (account, OAuth app, Protection plan, Playground token, staging user) — unblocks
   everything, off the coding critical path.
2. **Audio spike, WebView-first (Tier 1.1)** — go/no-go this week.
3. Lock the captions-only fallback scope (Tier 1.2).
4. Reposition the pitch to two-way (Tier 1.3).
5. Ugly end-to-end skeleton by the 25% mark.
6. Emotional open + haptic moment + confidence captions (Tier 2) during build.
7. Friction log, both mini-challenges, WCAG statement (Tier 3) throughout, not at the end.

**Highest-leverage single action: the spike, this week. Everything else is downstream.**
