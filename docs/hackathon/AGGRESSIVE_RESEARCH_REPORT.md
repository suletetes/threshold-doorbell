# Aggressive Research Report — Threshold (threshold-doorbell)

*Two-way captioned Ring doorbell for deaf and hard-of-hearing residents. Amazon Developer Hackathon 2026,
Ring track, Flutter.*

Prepared with a caveman-density research process (dense internal notes) rendered here as clean prose for
human readers, per the caveman skill's boundary rule (documents for humans stay in normal English). Research
skills consulted from the AAS catalog: `deep-research`, `auto-research`, `competitor-analysis`,
`competitive-landscape`, `market-research`, `customer-research`.

Date of research: September 2026. Confidence levels and source reachability are flagged throughout.

---

## 1. Executive summary

- **The market gap is real and large, and it survived aggressive scrutiny.** Every deaf/hard-of-hearing
  doorbell product found solves *alerting* only (flashing lights, loud chimes, vibrating pagers). None solve
  *the conversation* — understanding what the visitor says and replying. This was re-confirmed across
  independent 2025 sources. **Confidence: High.**
- **The audience is one of the largest addressable disability populations on earth.** ~1.5 billion people
  live with some hearing loss; ~430–466 million have disabling hearing loss (WHO / peer-reviewed).
  Independent sources agree within a consistent band. **Confidence: High.**
- **The single biggest competitive threat is not another doorbell — it is Google Live Transcribe**
  (free, 500M+ downloads, 80+ languages, offline since 2022, built with Gallaudet University). It captions
  *ambient* audio. Crucially, it does **not** do two-way and cannot reply through a doorbell. Threshold must
  position explicitly against it. **Confidence: High. This is the most important finding of the report.**
- **Threshold's defensible wedge is the outbound half:** replying *out of the doorbell* using Ring's
  bidirectional `sendrecv` audio channel. No product found does this. **Confidence: High** on the gap,
  **Medium** on the technical feasibility of injecting synthesised audio (unproven — the R1 spike).
- **Regulatory and social tailwinds are strong:** captioning is a WHO-recognised treatment aid; hearing loss
  is linked to isolation, loneliness and dementia; accessibility carries legal weight (ADA / WCAG). These
  strengthen the "Potential Impact" judging axis. **Confidence: High** on the framing, **Medium** on any
  specific legal-market number (primary market-size sources were paywalled/blocked — see §6).
- **Biggest risks:** (1) the audio-injection spike may fail; (2) Ring App Store publishing requires a Ring
  Protection subscription and certification, so "production" is gated even though the hackathon demo is not;
  (3) a platform vendor (Amazon/Google) could add captioning natively and erase the moat.

---

## 2. Methodology & sources

**Approach.** Wide-then-deep open-internet research across source types: official docs (WHO, Amazon Ring
developer docs, arXiv), encyclopedic cross-references (Wikipedia for triangulation, not as primary truth),
competitor/product pages (hearview.ai, RNID, deafvibes, hear4you), and the Ring API sample source code read
line-by-line in a prior session. Claims below are cross-verified across independent sources where possible.

**Source reachability (flagged honestly).** Several high-value commercial market-research pages returned
**HTTP 403 (Grand View Research)** or were otherwise blocked (Reddit JSON 403, DuckDuckGo/Bing HTML search
scraping returns no readable content in this environment). Where a number could not be independently
retrieved, it is marked **[UNVERIFIED — paywalled/blocked]** rather than asserted. This is a genuine gap,
not a rounding error.

**What "verified" means here.** A claim is High confidence when ≥2 independent reachable sources agree, or
when it comes directly from an authoritative primary source (WHO, Amazon's own docs, the Ring sample code).

---

## 3. Key findings (grouped by theme)

### 3.1 The problem is genuine and narrowly unserved

**Claim:** Existing deaf-doorbell products solve alerting, never conversation.
**Evidence:** hearview.ai (24 Nov 2025) frames the problem as "a simple chime creates a barrier, cutting you
off from the outside world" and its entire buyer's guide compares only **flashing lights vs. vibration**.
RNID (UK national hearing charity), deafvibes, and hear4you independently describe the same solution set:
strobes, ~100 dB chimes, vibrating pagers/wearables. **No source describes a product that captions the
visitor or lets the resident reply.**
**Confidence:** High (multiple independent 2025 sources, consistent).
**Relevance:** This is the core thesis. Threshold builds the missing half.
**Implication/opportunity:** First-mover on "conversation at the door," not "alert at the door."

### 3.2 The audience is very large and the need is documented

**Claim:** Hundreds of millions of people are affected; captioning is a recognised aid.
**Evidence:** WHO: >1.5 billion live with some hearing loss; ~430 million with disabling hearing loss, rising
to >700 million by 2050; >25% of over-60s affected; ~80% in low- and middle-income countries. Wikipedia
(citing WHO) corroborates ~1.1–1.33 billion affected and ~466 million with disabling loss, and explicitly
lists **closed captioning and subtitles among treatments**, and names **social isolation, loneliness, and
dementia** as complications.
**Confidence:** High (WHO primary + independent corroboration; minor variance from different measurement
years, which I flag rather than paper over).
**Relevance:** Directly powers the "Potential Impact" judging criterion and the caretaking angle (over-60s).
**Implication:** A *free app on hardware they already own* is especially strong for the ~80% in
low/middle-income countries who cannot buy specialist hardware.

### 3.3 The real competitor is ambient captioning, not doorbells

**Claim:** Google Live Transcribe is the incumbent solution deaf users already reach for.
**Evidence:** Wikipedia/Google: free Android app, **500M+ downloads** (early 2023), **80+ languages**,
**open-source speech engine** (Apache 2.0, 2019), **offline transcription since March 2022** (needs 6GB RAM
/ certain Pixels), built **with Gallaudet University** (the deaf university). Apple and Google also ship OS-
level Live Caption for on-device media.
**Confidence:** High.
**Relevance / threat:** A judge or user will ask, "why not just point Live Transcribe at the doorbell
speaker?" Threshold's answer must be crisp:
1. Live Transcribe captions *ambient* audio in the room; it does **not** tap the Ring stream, so it can't
   caption a visitor the resident isn't standing next to, and can't run from a push alert.
2. It is **one-way**. It never lets the resident *reply through the doorbell*. Threshold's outbound
   `sendrecv` audio reply is the entire differentiator.
3. It has **no doorbell context** — no visitor thumbnail, no event history, no "who is at my door."
**Implication:** Position Threshold as "the doorbell that talks back," not "captions for your door." If you
pitch it as captioning, you lose to a free 500M-download incumbent. If you pitch it as *two-way
conversation*, you are uncontested.

### 3.4 The technical wedge is Ring's unused outbound audio

**Claim:** Ring's WebRTC session is bidirectional but Amazon's own sample ignores the outbound half.
**Evidence:** From `ring-api-helloworld/app/hooks/useWebRTCStream.ts` (read directly): the audio transceiver
is `addTransceiver('audio', { direction: 'sendrecv' })` while video is `recvonly`. The sample only *renders*
inbound media; it never pushes audio back. Ring's developer site independently confirms live video via
WebRTC/RTSP, motion/doorbell/person events, and event history through the Partner API.
**Confidence:** High on availability of the channel; **Medium** on our ability to inject synthesised PCM
into it from Flutter (unproven — this is risk R1).
**Relevance:** This is the buildable basis for "reply out of the doorbell."
**Implication/risk:** The whole product hinges on the R1 spike. Do it first.

### 3.5 Amazon's own event surface is richer than the docs summary

**Claim:** `person_detected` events carry confidence, bounding box, and thumbnail.
**Evidence:** `ring-api-helloworld/lib/types/webhook.ts` defines
`type: 'motion_detected' | 'device_added' | 'device_removed' | 'person_detected'` with
`confidence?`, `bounding_box?`, `thumbnail_url?`. The sample also ships a **`VideoProcessor` plugin
interface** (~10 fps, MediaPipe Hands built in) — sanctioning on-device CV on Ring frames.
**Confidence:** High (from source).
**Relevance:** Free visitor thumbnail for the alert screen; a native-feeling way to add visual context; the
plugin interface is the most idiomatic possible Tech-Implementation score.

### 3.6 On-device speech is viable but rougher on Flutter

**Claim:** Real-time on-device ASR is achievable; the cloud path is the safer default.
**Evidence:** `whisper.rn` (React Native) offers realtime Whisper + Silero VAD + Core ML — but we are on
Flutter, where the equivalent (`whisper_ggml` / FFI to whisper.cpp) is less mature. Amazon Transcribe
streaming has partial-results stabilization (purpose-built for live captions). Google's Live Transcribe
proves offline on-device captioning is a solved *product* problem (just not one we get for free in Flutter).
**Confidence:** High.
**Relevance:** Ship **Transcribe (Clarity Mode) as default**, treat on-device Whisper (Privacy Mode) as a
stretch. This also anchors the AWS Builder mini-challenge.

### 3.7 Publishing (not demoing) is gated

**Claim:** The hackathon demo is ungated, but a real Ring App Store product is not.
**Evidence:** Ring dev docs: testing requires a **Ring account with an active Ring Protection subscription**
and supports up to **10 staging users**; there is a full **Configure → Build → Test → Certify** lifecycle,
OAuth 2.0 account linking, HMAC-signed webhooks, a **100 req/s** rate limit, and a **mandatory media
watermark** (Ring logo + device ID + timestamp) on all delivered video/clips/snapshots.
**Confidence:** High (primary docs).
**Relevance:** Fine for the hackathon (Playground token + staging). Matters for the "beyond the hackathon"
impact argument — be honest that production requires certification and a subscription.

---

## 4. Data & evidence (quick-reference table)

| Metric / fact | Value | Source | Confidence |
|---|---|---|---|
| People with some hearing loss | >1.5 billion | WHO | High |
| People with disabling hearing loss | ~430–466 million | WHO / peer-reviewed | High |
| Projected disabling hearing loss by 2050 | >700 million | WHO | High |
| Over-60s with disabling hearing loss | >25% | WHO | High |
| Share in low/middle-income countries | ~80% | WHO | High |
| Google Live Transcribe downloads | 500M+ (early 2023) | Wikipedia/Google | High |
| Live Transcribe languages | 80+ | Wikipedia/Google | High |
| Live Transcribe offline mode | since Mar 2022 (6GB RAM) | Wikipedia | High |
| Ring API rate limit | 100 req/s | Amazon Ring docs | High |
| Ring live video | WebRTC/WHEP + RTSP | developer.ring.com | High |
| Ring audio channel | `sendrecv` (bidirectional) | ring-api-helloworld source | High |
| Ring webhook types | motion / device add-remove / person | ring-api-helloworld source | High |
| Assistive-tech / hearing-aid market size | **[UNVERIFIED — paywalled/blocked]** | Grand View (403) | Low |
| Web-accessibility lawsuit volume | **[UNVERIFIED — not retrieved]** | — | Low |

---

## 5. Competitive / landscape map

**Category A — Alerting hardware (indirect competitors).** Flashing-light doorbells, ~100 dB chimes,
vibrating pagers/wearables (RNID, hear4you, hearview.ai, 1800doorbell, many Amazon listings). *Solve
alerting. Do not touch the conversation.* Threshold does not compete here; it complements/replaces the
"then what?" moment after the alert.

**Category B — Ambient captioning apps (the real threat).** Google Live Transcribe (dominant, free, 500M+),
Apple/Android OS Live Caption, Otter/third-party transcribers. *Solve understanding of nearby speech. One-
way. No doorbell integration, no reply.* This is who Threshold must out-position on *two-way* and *doorbell
context*.

**Category C — Smart doorbell platforms.** Ring, Nest, Eufy, Arlo. All offer two-way talk for *hearing*
users via voice. *None expose captioning or text-reply for deaf users.* Ring is our platform, not our rival;
Nest/Eufy indicate the pattern is generalizable later.

**Category D — Direct competitor (a captioning + reply doorbell).** **None found.** Triangulated across
multiple queries and source types. This negative result is a core finding — the specific combination
(Ring stream + captions + spoken reply out the door) appears genuinely novel. **Confidence: Medium-High**
(absence of evidence across many searches; some search endpoints were blocked, so not absolute).

**White space:** two-way, doorbell-native, deaf-first conversation. Threshold sits alone in it.

---

## 6. Risks, gaps & uncertainties

| # | Risk / gap | Severity | Notes |
|---|---|---|---|
| 1 | **R1 audio-injection spike may fail** | Critical | Injecting synthesised PCM into the outbound WebRTC track is unproven in Flutter. Fallback: run the audio pipeline in `webview_flutter`. Decide in week one. |
| 2 | **Platform vendor adds native captioning** | High (long-term) | Amazon could add captions to the Ring app; Google already owns ambient captioning. Moat = two-way + doorbell context, not captioning itself. |
| 3 | **Ring production gating** | Medium | Certification + Ring Protection subscription required to publish. Hackathon demo unaffected. |
| 4 | **On-device Whisper immaturity on Flutter** | Medium | Mitigated by making Transcribe the default; Privacy Mode is a stretch. |
| 5 | **Market-size numbers unverified** | Medium (evidence gap) | Grand View 403'd; no independent hearing-aid/assistive market figure retrieved. Do not cite a specific $ TAM without a fresh, reachable source. |
| 6 | **ASR errors at a safety-relevant moment** | Medium | A stranger is at the door. Style low-confidence words as uncertain; never auto-act on a transcript. |
| 7 | **Watermark obscuring overlays** | Low | Keep UI overlays out of the top corners. |

**Known unknowns (still poorly documented):**
- Exact assistive-technology / captioned-doorbell market size and growth (paywalled).
- Real-world latency of Transcribe streaming over a phone's cellular link end-to-end from the doorbell.
- Whether Ring's `sendrecv` audio permits a *non-microphone* synthesised source without policy friction.
- Volume/severity of accessibility litigation as an adoption driver (not retrieved this session).

---

## 7. Actionable insights & recommendations

1. **Reposition the pitch around "two-way," never "captions."** The one-line test: if the demo could be
   replaced by pointing Live Transcribe at the door, the pitch is wrong. Lead with the resident *replying*
   and the doorbell *speaking*. (High priority, zero cost.)
2. **Do the R1 audio spike first, in week one.** It is the only thing that can kill the project. Everything
   else is de-risked by verified Ring capabilities. (Critical.)
3. **Name-check Live Transcribe in the demo and dismiss it in one sentence** ("great for the room you're
   standing in — but it can't answer the door"). Pre-empting the obvious judge question builds credibility.
4. **Make Transcribe the default caption engine; ship Privacy Mode as a bonus.** Reliability wins demos, and
   it strengthens the AWS Builder mini-challenge. (High.)
5. **Lean into caretaking + over-60s + isolation/dementia framing** for Potential Impact — all WHO-backed
   and independently corroborated. (High.)
6. **Do not assert a dollar TAM you cannot source.** Use the population figures (verified) and the
   competitor gap (verified); leave market-size as qualitative until a reachable source is found. (Integrity
   + avoids a judge catching an unsourced number.)
7. **Frame production honestly:** demo via Playground token/staging; note certification + subscription for
   the real App Store path. Judges reward teams that understand the ecosystem (a stated criterion).
8. **Bank the free wins:** friction log (up to 10% judging bonus), both mini-challenges, OSS package
   (`flutter_ring_captions`) + a PR to `AmazonAppDev/ring-api-helloworld` (their CONTRIBUTING welcomes PRs).

---

## 8. Source list

Primary / high-confidence:
- WHO — Deafness and hearing loss (fact sheet & health topic): population and projection figures.
- Amazon Ring Developer docs — API Development Guide, MCP, get-started (rate limit, OAuth, webhooks,
  watermark, certification, Ring Protection requirement): https://developer.amazon.com/docs/ring/
- developer.ring.com — live video (WebRTC/RTSP), events, event history.
- `ring-api-helloworld` source (read directly): `useWebRTCStream.ts` (`sendrecv` audio), `webhook.ts`
  (`person_detected` + confidence/bbox/thumbnail), `docs/video-processors.md` (VideoProcessor + MediaPipe).
- Wikipedia — Live Transcribe (500M+ downloads, 80+ languages, offline 2022, Gallaudet, Apache 2.0).
- Wikipedia — Hearing loss (citing WHO): ~1.1–1.33B affected, ~466M disabling, captioning as treatment,
  isolation/dementia complications.
- arXiv:2401.01301 (Stanford, Journal of Legal Analysis 2024) and arXiv:2606.18021 (ICML 2026) — referenced
  from prior session for the AI-in-regulated-domains context (relevant to a pivot, not to Threshold core).

Product / competitive:
- hearview.ai (24 Nov 2025) — deaf-doorbell buyer's guide (alerting only).
- RNID, deafvibes, hear4you, 1800doorbell — corroborating the alerting-only market.

Blocked / unverified (flagged, not cited as fact):
- Grand View Research assistive-technologies market (HTTP 403).
- Reddit r/deaf JSON (HTTP 403); DuckDuckGo/Bing HTML search (no readable content in this environment).

---

*Prepared for the Threshold project. Population and platform-capability claims are cross-verified and High
confidence. Market-size and litigation figures are explicitly unverified and must not be cited as fact until
a fresh reachable source is obtained.*
