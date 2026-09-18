# Product Steering — Threshold

## What this is

Threshold is a mobile app (iOS + Android, Flutter) that turns a **Ring video doorbell** into a **two-way,
text-based conversation device for people who are deaf or hard of hearing**. When a visitor speaks, the
resident sees **live captions** on their phone. When the resident taps or types a reply, a synthesized voice
is **spoken out of the doorbell** so the visitor hears it.

Built for the Amazon Developer Hackathon 2026 — **Ring** primary track, with the **AWS Builder** (Amazon
Transcribe + Bedrock) and **Open Source** mini-challenges.

## Who it serves

- **Primary — deaf/HoH residents** (persona: Priya, 34, profoundly deaf, lives alone). Today her doorbell
  tells her *someone* is there but never *what they want*.
- **Secondary — older residents with age-related hearing loss** (persona: Bernard, 78). Ties the product to
  Ring's **caretaking** category as well as **accessibility**.
- **Visitor** is a non-user external actor: heard (for captions) and spoken to (reply audio). No account, no UI.

## The core insight (do not lose this)

Ring's WebRTC session negotiates audio as **`sendrecv`** — bidirectional — but the canonical Ring sample
uses only the inbound half. The **defining capability of Threshold is the outbound reply through the
doorbell**, built on the channel everyone else leaves idle. Captions alone would lose to free incumbents
(Google Live Transcribe: 500M+ downloads, one-way, doorbell-blind). **Position and build around two-way,
never captions-only** — except as the deliberate fallback (below).

## Product principles

1. **Not a chatbot.** AI does only perception (speech→text), synthesis (text→speech), and ≤3 suggested
   replies. No assistant persona, no open-ended chat. If a change drifts toward "AI wrapper," reject it.
2. **Captions are the interface**, not a secondary label.
3. **Never present a guess as certain.** Low-confidence words render visibly uncertain. A stranger is at the
   door; safety over polish.
4. **Privacy is architectural.** Privacy Mode runs ASR on-device with zero audio egress. No raw audio/video
   is ever persisted — only text transcripts.
5. **Accessibility is the product, not a feature.** WCAG 2.2 AA on every screen (Ring's partner UX guide
   mandates it). Fully usable with sound off and a screen reader on.
6. **The phone becomes the doorbell.** Distinct haptic patterns per event; screen strobe/torch as a software
   flashing-light.
7. **One legible demo beats a feature list.** Protect the single wow moment: a deaf person holding a
   conversation at their door.

## Scope discipline

**In scope:** account linking, alerts, live session, captions (cloud default + on-device stretch), spoken
reply, smart replies, searchable text transcripts, haptics, accessibility, settings.

**Out of scope (do not build):** conversational AI, live translation, sign-language recognition, Fire
TV/Alexa companion, our own account system, storing audio/video, non-Ring doorbells, a certified production
App Store release within the hackathon window.

**Deliberate fallback:** if outbound audio injection is proven unavailable, ship **Captions-Only Mode** as a
first-class, fully-tested product (captions + a visitor-facing prompt), not an error state.

## Definition of success

A resident completes a full two-way exchange — visitor speaks → caption → resident replies → reply audible
at the door → visitor responds → caption — in a live demo, without hearing and without a mock.
