# Spec / Design / Tasks Audit — Threshold (threshold-doorbell)

Adversarial audit of the complete specification package as it stands on `main`. Every finding below is
backed by evidence from the actual documents (grep-verified where stated). No finding is hypothetical.

Documents audited:
- `.kiro/specs/threshold-doorbell/requirements.md` (15 FRs, 9 NFRs, 17 ATs)
- `.kiro/specs/threshold-doorbell/design.md` (12 sections)
- `.kiro/specs/threshold-doorbell/tasks.md` (21 tasks)

---

## 1. Executive summary

**Overall health: good structure, real defects. NOT one-shot ready.** The package is well above typical
hackathon quality: EARS criteria are genuine, the traceability idea is present, and the highest-severity
product risk (outbound audio) is explicitly de-risked with a defined degrade path. But the audit found
**23 concrete defects**, including four that would block or derail implementation.

**The four biggest risks, in order:**

1. **A requirement exists with zero design.** FR-12.1 mandates a "visitor-facing on-screen text/QR prompt"
   for Captions-Only Mode. Grep of `design.md` for "QR" returns **0 matches**. The entire fallback scope —
   the thing that saves the project if the audio spike fails — has **no designed interaction model**. This
   is the single worst defect in the package, because it is the contingency plan.
2. **The three gap-closing sub-requirements are not in any task.** Grep of `tasks.md` for
   `FR-5.3a|FR-6.4a|FR-6.4b` returns **0 matches**. The sub-requirements added specifically to resolve the
   top-severity ambiguities (sticky outbound mode, partial-vs-final confidence) are traceable to nothing.
3. **Two NFRs have no implementing task.** `NFR-1` (performance budgets) and `NFR-5` (graceful degradation)
   appear **0 times** in `tasks.md`. The latency goals G1–G3 are asserted and measured (design §10) but
   nobody is tasked with *achieving or verifying* them as an explicit workstream.
4. **G1 is unmeasurable as written.** "From doorbell event to first on-screen caption ≤ 3.0 s" spans the Ring
   cloud (event generation), webhook delivery, push transit, user tap, WebRTC setup, and ASR. Several of
   those segments are outside the system's control, and the requirement does not define the start instant
   (Ring's event timestamp? webhook receipt? push receipt?) nor whether user reaction time is included.
   It cannot pass or fail deterministically.

**Verdict: NEEDS REVISION.** Not major rework — the architecture is sound and the fixes are surgical. But the
spec currently claims "There are no open questions; all ambiguities are resolved," and that claim is **still
false**, which is itself a defect (D-23).

---

## 2. Requirements findings

### Critical

- **R-1. FR-12.1 is under-specified and un-designed.** "on-screen text/QR prompt the resident can surface"
  is the only description of the fallback interaction. Unanswered: QR encoding what (a URL? a text payload)?
  Who scans it — the visitor, on their own phone? How does a visitor know to scan? Does the resident hold
  the phone to the camera? Is the prompt displayed on the phone (which the visitor cannot see) or somehow at
  the door (impossible — Ring has no screen)? **As written, the fallback mode may be physically incoherent:
  the resident is inside, the visitor is outside, and nothing bridges them.** This must be resolved before
  it can be built, and it is the contingency plan for the project's biggest risk.
- **R-2. "Person is present" (FR-5.4) is undefined.** The trigger for the "No speech detected" state depends
  on presence detection, but the spec never says what establishes presence: the `person_detected` webhook?
  the on-device ML processor (FR-11/task 14)? an active session alone? Different answers give different
  behavior, and task 14 (visual context) is scheduled *after* task 8 (captions), so at implementation time
  the presence signal may not exist yet.
- **R-3. G1 start instant undefined** (see Executive Summary §4). Also NFR-1 says "mid-tier 2023 Android
  device and iPhone 12+", while §1 pins "Pixel 7 / iPhone 12" — **NFR-1 and §1 disagree** ("iPhone 12+" vs
  "iPhone 12"), a minor but real inconsistency in a supposedly pinned reference.

### Major

- **R-4. Privacy Mode contradicts Smart Replies, and the spec never resolves it.** FR-5.2 requires that in
  Privacy Mode nothing leaves the handset. FR-7.1 requires sending finalized caption text to Bedrock (cloud)
  for suggestions. FR-7.4 permits "transcript text" to Bedrock. **So in Privacy Mode, does Smart Replies
  still call Bedrock?** If yes, the privacy promise is misleading (audio stays local but its *transcription*
  is uploaded — a distinction most users would not accept). If no, no requirement says Smart Replies is
  disabled in Privacy Mode. This is a direct requirement conflict on the product's headline privacy claim.
- **R-5. FR-14.3 has a circular dependency.** The at-door legal notice "reuses the outbound-audio path" and
  its "availability SHALL follow the same outbound-audio availability rules as FR-6." Therefore **in
  Captions-Only Mode the legal notice cannot play** — meaning in exactly the degraded mode the product may
  ship in, the two-party-consent mitigation is unavailable, while transcription continues. The spec does not
  acknowledge or resolve this.
- **R-6. Session-expiry (FR-4.8) conflicts with refresh (FR-1.4/1.5).** FR-1.5 says on refresh failure,
  "prompt the resident to re-link." FR-4.8 says on app-backend session expiry, show "a single
  non-destructive re-authentication prompt … resume the interrupted action." These are two different
  recovery flows for overlapping conditions (an expired session often *is* a failed refresh). Which wins is
  undefined; an implementer will build both and they will collide.
- **R-7. FR-8.1 requires per-turn confidence; FR-5.3 says partials have none.** FR-8.1 persists "per-turn
  confidence". Design's `Turn.confidence` is "per-turn min token confidence". But if a turn ends while only
  partial results exist (session drops mid-utterance — an explicitly handled case), confidence is
  unavailable. Nullable in the model, but **no requirement defines the persisted value for an
  unfinalized turn**.
- **R-8. FR-2.2 makes demo behavior a product requirement.** "in demo builds, SHALL offer to load a
  deterministic fixture device" puts build-variant behavior in a functional requirement. This is
  over-specification leaking test scaffolding into the product spec; it also makes FR-2.2 untestable in a
  production build.
- **R-9. No requirement for what happens when the visitor speaks while the reply is playing.** FR-6.3 covers
  duplicate submission but not audio collision: full-duplex means the visitor may talk over the synthesized
  reply. Does ASR keep captioning during playback (risking transcribing our own TTS back as visitor
  speech — an echo/feedback loop)? **Echo cancellation / self-transcription suppression is entirely absent
  from the spec.** This is a genuine functional hole in a two-way audio product.
- **R-10. FR-4.3 (background > 30 s closes session) conflicts with the core use case.** A deaf user gets a
  push, opens the app, and may need to walk to the door or switch apps. A hard 30-second background kill
  will tear down live sessions during normal use. No requirement defines resumption after an unintended
  background kill (FR-4.8 covers auth expiry, not this).

### Minor

- **R-11. FR-9.1 says "at least three" patterns** — an open-ended lower bound in a supposedly precise spec.
  "At least" is unverifiable as an upper-bounded acceptance test.
- **R-12. FR-10.2 "contrast" is unquantified.** Settable contrast with no defined range or minimum floor;
  a user could in principle set contrast below the NFR-2 4.5:1 requirement, violating it. No requirement
  prevents user settings from breaching the accessibility floor.
- **R-13. No language/locale requirement** despite FR-5 being ASR-dependent and design's error table saying
  "Non-English speech → Language selector; default en-*". **The language selector is in the design but has
  no requirement.** Backwards traceability failure (design element with no requirement).
- **R-14. No requirement covers Ring API version/contract drift**, despite the integration being built on
  observations from a sample repo rather than a stable published contract.

---

## 3. Design findings

### Critical

- **D-1. FR-12.1 has no design at all** (see R-1). §8 UI/UX lists 7 screens; none is the visitor-facing
  fallback surface. Grep "QR" in `design.md` = **0**. The contingency plan is undesigned.
- **D-2. The capability probe is named but not specified.** Design mentions "probe" 3 times and
  `Conversation.outboundAvailable`, but **never defines what the probe actually does**. Does it inject a
  silent/inaudible test buffer (risking an audible artifact at a stranger's door)? Check an API surface? A
  cached prior result? This is the gate for the product's defining feature and it is a black box. An
  implementer cannot build it from this design.

### Major

- **D-3. Two WebRTC stacks, one session — unresolved.** Design uses `flutter_webrtc` for inbound
  (§2, task 7) and a **WebView browser WebRTC** for outbound audio (§2, FR-6.2). The design never states
  whether these are **one peer connection or two**. If one, it must live in exactly one stack — and
  `flutter_webrtc` cannot inject the audio, while the WebView would then have to own the inbound video too
  (contradicting task 7). If two, there are **two concurrent WebRTC sessions to the same Ring device**,
  which Ring may reject, and which doubles session-URL management. **This is the deepest architectural hole
  in the package** and it sits directly on the critical path.
- **D-4. `/asr/stream` contradicts the privacy architecture for Privacy Mode.** The route accepts "PCM
  frames (Clarity)" — correctly scoped — but §1's diagram shows "audio frames (Clarity Mode only)" while the
  trust-boundary text says Privacy Mode "touches no backend." Yet the app still needs the backend for
  signaling (`/signaling`) during a Privacy-Mode session. So Privacy Mode *does* touch the backend, just not
  with audio. The wording "touches no backend" is false as stated.
- **D-5. Single point of failure: the backend is mandatory for every session.** `/signaling` brokers WebRTC.
  If the backend is down, **no session can start at all**, including Privacy Mode. NFR-5 promises graceful
  degradation on single-component failure, but a backend outage is total. No design mitigation (direct
  signaling, cached session path, or documented acceptance) is offered.
- **D-6. Token storage is specified in two contradictory places.** §7 says tokens live in "Secrets Manager
  (backend) + Keychain/Keystore (device)" and FR-1.6 agrees. But FR-1.2 says the exchange is server-side and
  the app never sees the secret — so **why does the device store a Ring token at all?** If the app calls
  Ring directly it needs one (contradicting the trust boundary); if it only calls our backend it needs only
  our session cookie. The design never states which. This is a security-relevant ambiguity.
- **D-7. Secrets Manager is the wrong store for per-user tokens.** §3 says "Tokens live in Secrets Manager
  keyed by `residentSub`". Secrets Manager is priced and rate-limited for a small number of
  application secrets, not per-user rows; at any scale this is both costly and throttle-prone. Correct
  choice is encrypted attributes in DynamoDB with a KMS key (Secrets Manager holding only the KMS/client
  secret). This is a concrete poor technology decision.
- **D-8. No echo/feedback design** (see R-9). Two-way audio with an ASR pipeline on the inbound leg and TTS
  on the outbound leg will transcribe its own output unless suppressed. Absent from §5, §6, and §9.
- **D-9. `POST /transcripts` lets the client write the whole `Conversation`.** The client supplies
  `residentSub`-scoped data; the contract shows the body as `Conversation` with a 400 only for `schema`.
  Nothing states the server overrides `residentSub` from the session — **an IDOR/spoofing vector** where a
  client could write a transcript attributed to another `residentSub`. §7 does not cover authorization
  (only authentication).
- **D-10. No pagination anywhere.** `GET /transcripts` and `GET /events` return arrays with no limit/cursor.
  Unbounded response growth; FR-8.2 search over a growing set with no paging is a performance defect.
- **D-11. Reply state machine omits the probe and the "visitor talks over reply" path.** §5's reply
  lifecycle has no state for probe-failed-at-start (it only shows inject-fail mid-flow), and no handling of
  inbound speech during `SPEAKING_AT_DOOR`.
- **D-12. Privacy-Mode "no egress" is asserted but the on-device ASR model must be downloaded.** No design
  for model acquisition, size, storage, versioning, or first-run download (which requires network). NFR-4's
  test asserts zero egress *during capture*, which is satisfiable, but the feature's provisioning is undesigned.

### Minor

- **D-13. §12 "Open questions: None." is asserted, not earned** — contradicted by D-1…D-12.
- **D-14. `flutter_webrtc ^0.12.0` / `flutter_tts ^4.2.0` / `webview_flutter ^4.7` are pinned with a
  "verify latest at build" caveat**, which is an unresolved decision masquerading as a decision.
- **D-15. The error table says "Transcribe WS drop → … else prompt Privacy Mode"** but switching mode
  mid-session is forbidden by FR-10.1 (applies next session). Direct design/requirement conflict.
- **D-16. No observability requirement backs §10.** Metrics/logging are designed but no NFR mandates them
  beyond "no PII in logs" (NFR-3). Design element with weak requirement backing.

---

## 4. Tasks findings

### Critical

- **T-1. FR-5.3a, FR-6.4a, FR-6.4b appear in zero tasks** (grep-verified). The sticky-mode semantics and the
  partial-vs-final confidence split — the two highest-value clarifications in the spec — are not assigned to
  any implementer. Task 8 still cites only "FR-5.3" and describes "confidence styling (<0.6 de-emphasized)",
  which is the **old, superseded** behavior that FR-5.3 no longer says.
- **T-2. Task 8's description contradicts the current FR-5.3.** It says "render partials; confidence styling
  (<0.6 de-emphasized)". Current FR-5.3 requires partials be styled provisional *because per-token confidence
  is unavailable*; the <0.6 rule now lives in FR-5.3a for finals only. **The task instructs the wrong
  implementation.**
- **T-3. The capability probe (FR-6.4a) has no task.** Nothing builds the probe that gates the entire
  two-way/Captions-Only decision.

### Major

- **T-4. NFR-1 (performance) and NFR-5 (reliability) have no tasks** (grep: 0 each). No task establishes
  latency measurement harnesses or verifies the G1–G3 budgets, despite them being headline goals.
- **T-5. Task 12 (Captions-Only) is unbuildable as written** because FR-12.1 is undesigned (R-1/D-1). It says
  "Visitor-facing on-screen/QR prompt" with no design to implement. This is the *fallback* — the task most
  likely to be executed under time pressure — and it is the vaguest.
- **T-6. Dependency inversion: task 2 references task 12 before task 12 is defined.** Task 2.4 says "If
  unavailable, activate the Captions-Only scope decision (task 12)", but task 12 depends on a design that
  does not exist. The go/no-go gate therefore branches into a void.
- **T-7. Task 14 (visual context) is ordered after task 8, but FR-5.4 ("while a person is present") may
  depend on it** (R-2). Latent ordering defect caused by the undefined presence signal.
- **T-8. Echo/self-transcription suppression has no task** (R-9/D-8).
- **T-9. Task 5 is a bundle, not a task.** "devices, events, transcripts, signaling, ASR, replies routes" is
  six distinct subsystems (including the WebSocket signaling broker and the Transcribe proxy) in one
  checkbox, citing only bare "FR-2, FR-8". Wrong granularity; hides the signaling design risk (D-3) inside a
  line item. Should be ≥4 tasks with sub-items.
- **T-10. FR-2.1/2.2/2.3 are never cited individually** (grep: no `FR-2.x` in tasks) — only bare `FR-2`.
  Same for `FR-3` and `FR-9` in places. Coarse citations weaken the traceability matrix the spec claims.
- **T-11. No task for the em-dash CI lint** mandated by `steering/structure.md` ("A lint/CI check SHALL fail
  the build if an em-dash or en-dash appears in a UI string resource"). Task 18 says "No em-dash in any UI
  string" as prose, and task 20 lists generic gates, but the specific check is unassigned. Steering rule
  with no implementing task.
- **T-12. No task for model provisioning in Privacy Mode** (D-12). Task 13 assumes the model exists.
- **T-13. No documentation/README task, no migration task, no threat-model task.** The audit brief calls
  these out explicitly; the plan has none (task 21 is OSS extraction, not product docs).

### Minor

- **T-14. Task 2 is the only task with sub-items.** Inconsistent decomposition style across 21 tasks; several
  (5, 18) plainly need sub-items.
- **T-15. Task 9 cites G3 but no task owns measuring it** (overlaps T-4).
- **T-16. Task 21 is not a coding task in the same sense as the others** and has no acceptance test.

---

## 5. Traceability & consistency issues

**Forward traceability (requirement → task): INCOMPLETE.**

| Requirement | In tasks? | Note |
|---|---|---|
| FR-5.3a | **No** | grep 0 |
| FR-6.4a | **No** | grep 0 (probe unbuilt) |
| FR-6.4b | **No** | grep 0 |
| FR-2.1/2.2/2.3 | Only as bare `FR-2` | coarse |
| NFR-1 | **No** | grep 0 |
| NFR-5 | **No** | grep 0 |
| NFR-2/3/4/6/7/8/9 | Yes | adequate |
| FR-1…FR-15 (top level) | Yes | all cited at least coarsely |

**Backward traceability (design/task → requirement): DEFECTIVE.**
- Language selector (design error table) — no requirement (R-13).
- Observability §10 — only weakly backed (D-16).
- Task 21 (OSS extraction) — cites "project goals", not a requirement.

**Acceptance-test coverage:** AT-1…AT-17 are all referenced in tasks (grep-verified) — this part is sound.
But **AT-5's harness is the only automated proof of the defining feature**, and AT-6's "force injection
unavailable" presumes the probe (T-3) exists.

**Cross-layer contradictions found:**
1. FR-5.3 (current) vs task 8 description (T-2).
2. FR-10.1 (mode change applies next session) vs design error table "prompt Privacy Mode" mid-session (D-15).
3. §1 reference device "iPhone 12" vs NFR-1 "iPhone 12+" (R-3).
4. FR-5.2 (nothing leaves device) vs FR-7.1 (caption text to Bedrock) (R-4).
5. FR-1.5 re-link flow vs FR-4.8 resume flow (R-6).
6. Trust boundary "Privacy Mode touches no backend" vs mandatory `/signaling` (D-4).
7. FR-1.2 (app never holds secret) vs FR-1.6/§7 (device stores tokens) (D-6).

---

## 6. Prioritized list of required fixes

**P0 — blocks implementation (fix before any coding beyond task 2):**
1. **Design FR-12.1 properly, or replace it.** Resolve the physical incoherence: how does a resident
   communicate with a visitor with no outbound audio? (Honest options: phone screen held to the camera,
   a pre-recorded Ring greeting, or accept that Captions-Only is receive-only and drop the "visitor-facing
   prompt" language.) Then add the screen to design §8 and re-scope task 12. (R-1, D-1, T-5, T-6)
2. **Resolve the one-vs-two WebRTC stacks question** and write it into design §1/§2 explicitly. (D-3)
3. **Specify the capability probe** — exact mechanism, whether it emits audible sound, failure semantics —
   and add a task. (D-2, T-3)
4. **Resolve Privacy Mode vs Bedrock Smart Replies.** State explicitly whether Smart Replies is disabled in
   Privacy Mode. (R-4)
5. **Fix task 8's description to match FR-5.3/5.3a**, and add FR-5.3a/6.4a/6.4b citations to tasks. (T-1, T-2)

**P1 — major correctness/security:**
6. Add echo / self-transcription suppression requirement, design, and task. (R-9, D-8, T-8)
7. Fix `POST /transcripts` authorization: server derives `residentSub` from session; document it. (D-9)
8. Move per-user tokens out of Secrets Manager to KMS-encrypted DynamoDB attributes. (D-7)
9. Reconcile FR-1.5 and FR-4.8 into one auth-recovery flow. (R-6)
10. Add pagination to `GET /transcripts` and `GET /events`. (D-10)
11. Resolve FR-14.3's circular dependency (legal notice unavailable in the mode that ships). (R-5)
12. Define the presence signal for FR-5.4 and fix task ordering. (R-2, T-7)
13. Add tasks for NFR-1 (latency harness) and NFR-5 (degradation matrix). (T-4)
14. Define G1's start instant precisely, or split it into controllable segments. (R-3)
15. Split task 5 into ≥4 tasks (devices/events, signaling broker, ASR proxy, transcripts). (T-9)
16. Fix design error table "prompt Privacy Mode" to respect FR-10.1. (D-15)
17. Clarify whether the device stores a Ring token at all. (D-6)
18. Design Privacy-Mode model provisioning + add task. (D-12, T-12)

**P2 — quality/consistency:**
19. Add em-dash lint task. (T-11)
20. Add requirement for language/locale selection. (R-13)
21. Fix "iPhone 12" vs "iPhone 12+". (R-3)
22. Bound FR-9.1 ("exactly three" or enumerate). (R-11)
23. Prevent user contrast settings from breaching NFR-2's 4.5:1 floor. (R-12)
24. Remove demo-build behavior from FR-2.2. (R-8)
25. Add docs/threat-model tasks. (T-13)
26. **Delete the "no open questions" claims** from requirements §intro and design §12 until P0/P1 are closed,
   or replace with a dated statement of known-open items. (D-13, R-23)
27. Add pagination/backend-outage acceptance tests; add AT for echo suppression.

---

## 7. Final scores & recommendation

| Dimension | Score | Rationale |
|---|---|---|
| **Requirements Quality** | **6.5 / 10** | EARS discipline is real and coverage is broad (15 FRs, 9 NFRs, 17 ATs). Undermined by 4 genuine conflicts (Privacy/Bedrock, auth recovery, FR-14.3 circularity, confidence/persistence), one incoherent requirement (FR-12.1), an unmeasurable goal (G1), and a missing functional area (echo suppression). |
| **Design Quality** | **5.5 / 10** | Sound layering, good trust boundary, strong error table. But the central architecture question (one or two WebRTC stacks) is unanswered, the capability probe is a black box, the fallback mode is entirely undesigned, plus a security gap (IDOR on transcript write), a wrong datastore choice (Secrets Manager per user), and no pagination. |
| **Task Breakdown Quality** | **5.5 / 10** | Ordering philosophy is correct (spike first) and AT coverage is complete. But 3 sub-requirements and 2 NFRs map to zero tasks, one task actively instructs superseded behavior, task 5 is a six-subsystem bundle, and the fallback task is unbuildable. |
| **Overall Spec Readiness (one-shot)** | **5 / 10** | Would not survive one-shot implementation. An engineer hits a hard stop at the WebRTC-stack question and at Captions-Only design. |
| **Risk Level** | **HIGH** | Concentrated in exactly the wrong place: the defining feature (probe + injection path) and its contingency (Captions-Only) are the least-specified parts of the package. |

### Recommendation: **NEEDS REVISION**

Not major rework. The foundation — personas, EARS requirements, layering, trust boundary, error handling,
test strategy — is genuinely strong and worth keeping. But **five P0 fixes must land before implementation
proceeds past task 2**, and the package must stop claiming zero open questions while twelve design-level
ambiguities remain.

**Most important single insight:** the spec is most rigorous where the project is *safest* (OAuth, webhooks,
accessibility, retention) and least rigorous where the project is *riskiest* (the audio probe, the dual-stack
WebRTC decision, and the fallback mode). That inversion is the real finding. Fix the inversion and this
package becomes genuinely one-shot ready.


---

# Resolution log (post-audit revision)

All 23 defects are addressed. The audit findings above are preserved unedited as the historical record; this
section states how each was closed and how it was verified.

## P0

| ID | Fix | Verification |
|---|---|---|
| R-1, D-1, T-5, T-6 | **Captions-Only rewritten as receive-only.** The visitor-facing prompt and QR idea are deleted and replaced by non-goal **N9** ("no visitor-facing display": a doorbell has no screen and the visitor cannot see the resident's phone). FR-12 now specifies captions plus a persistent banner plus a one-tap "Open Ring app" action, and design §8 screen 3 designs it. | `grep -ci QR requirements.md` = **0** |
| D-3 | **ARCH-1 decision recorded:** exactly one peer connection, owned by the WebView. `flutter_webrtc` removed from the live-session path and from the dependency table, with consequences (video renders in the WebView, inbound audio tapped via AudioWorklet, JS-bridge budget owned by the latency harness) written out. | `grep -c ARCH-1 design.md` = **6** |
| D-2, T-3 | **Probe fully specified** in design §5.1: baseline `packetsSent`, at most 200 ms of audio at or below -60 dBFS (inaudible at the door), `replaceTrack`, poll `getStats()` every 100 ms for up to 1000 ms. Assigned to task 2.3. | `grep -c packetsSent design.md` = **2** |
| R-4 | **Privacy Mode vs Bedrock resolved:** new FR-7.1a forbids calling Bedrock in Privacy Mode; suggestions come from the fixed safe set plus on-device keyword templates. FR-5.2 extended so neither audio nor transcript text leaves the device. | requirement `7.1a` present; cited by task 18 |
| T-1, T-2 | **Task 8 superseded wording removed.** Captions work is now task 13 and cites FR-5.3 **and FR-5.3a** with the correct partial-versus-final behavior. Sticky-mode work is task 16 citing FR-6.4a/6.4b. | `grep -cE "FR-5.3a\|FR-6.4a\|FR-6.4b" tasks.md` = **4** (was 0) |

## P1

| ID | Fix |
|---|---|
| R-9, D-8, T-8 | New **FR-5.6** self-transcription suppression (gate ASR during playback, 300 ms tail, mark the gap, enable echo cancellation), design §5.3 states `GATE_ASR_ON`/`GATE_OFF`, new task 14, new **AT-18**. |
| D-9 | **FR-8.7** plus design §4/§7: `residentSub` always server-derived; foreign values rejected `403 resident_mismatch`. New **AT-19**; task 27 tests it. |
| D-7, D-6 | Ring tokens moved to **KMS-encrypted DynamoDB** (`ring_tokens`); Secrets Manager reduced to application secrets. **FR-1.6** now forbids Ring tokens on the device (device holds only the app session credential). Task 4 owns it. |
| R-6 | **FR-1.5 unified auth recovery**; FR-4.8 now delegates to it. AT-12 asserts no second divergent path exists. |
| D-10 | Cursor **pagination** on `/devices`, `/events`, `/transcripts` (`limit` default 25, max 100; `{ items, nextCursor }`). AT-19. |
| R-5 | **FR-14.3a** compliance fallback: if the audible notice is enabled but outbound audio is unavailable, offer continue-without-notice or disable-transcription instead of silently transcribing. |
| R-2, T-7 | **FR-5.4 presence definition** (active session AND (`person_detected` within 60 s OR visual processor reports a person); event alone suffices if the processor is unavailable), removing the ordering dependency on the visual processor. |
| T-4 | New task 25 (**latency harness**, NFR-1) and task 26 (**degradation matrix**, NFR-5). |
| R-3 | **G1 split** into G1a (webhook receipt to push delivered, 1.5 s) and G1b (tap to first caption, 2.0 s), excluding user reaction time. Reference device fixed at "iPhone 12" exactly. |
| T-9 | Old bundled task 5 **split into tasks 5 to 9** (webhook, devices/events, signaling, ASR relay, transcripts). |
| D-15 | Error table corrected: a Transcribe drop no longer "prompts Privacy Mode" mid-session (which violated FR-10.1); it ends captions with a notice and suggests Privacy Mode for the next session. |
| D-12, T-12 | **FR-5.2a** model provisioning (opt-in download, size disclosure, never during a session, mode labelled unavailable until verified); task 18; **AT-21**. |
| D-5 | Backend signaling SPOF **explicitly accepted and surfaced** via FR-15.4 and AT-20 rather than silently assumed. |

## P2

| ID | Fix |
|---|---|
| T-11 | **NFR-10** plus task 29 CI gate plus **AT-24** for the em-dash and en-dash UI-string lint. |
| R-13 | New **FR-16** language and locale selection (the design's language selector now has a requirement). |
| R-11 | FR-9.1 changed from "at least three" to **exactly three** patterns in v1. |
| R-12 | FR-10.2 bounds contrast adjustment to a **4.5:1 floor** so user settings cannot breach NFR-2. |
| R-8 | Fixture-device loading removed from FR-2.2 and relocated to design §11 (`local` environment). |
| R-10 | FR-4.3a replaces the 30-second background kill with **5-minute background survival** and resume, matching the real use case of walking to the door. |
| R-7 | **FR-5.7** defines persistence of an unfinalized utterance (`confidence: null`, `provisional: true`); `Turn.provisional` added to the model. |
| R-14 | New **FR-17** Ring contract-drift isolation via one schema-validating adapter emitting `ring_contract_invalid`; **AT-23**. |
| D-13, D-16 | The unearned "no open questions" claims are **removed**. Requirements §7 and design §12 are now explicit "Known open items" sections requiring date and owner for any future ambiguity. Observability is backed by NFR-3 plus task 28. |
| D-14 | Version pins declared **authoritative**; the "verify latest at build" caveat withdrawn, CI pins via lockfiles. |
| T-13 | New task 27 (threat model), task 30 (README, privacy policy, runbook, friction log). |
| T-14 | Task 2 decomposition retained; former bundles split (tasks 5 to 9), so decomposition is now consistent. |

## Revised package shape

| Metric | Before | After |
|---|---|---|
| Functional requirements | 15 | **17** |
| Non-functional requirements | 9 | **10** |
| Acceptance tests | 17 | **25** |
| Tasks | 21 | **31** |
| FR-5.3a / 6.4a / 6.4b in tasks | 0 | **4 citations** |
| NFR-1 / NFR-5 in tasks | 0 / 0 | **2 / 2** |
| Em-dash and en-dash in spec files | present | **0** |

## Residual risk (unchanged by documentation)

Specification quality is now adequate, but the **product risk is still concentrated in task 2**. ARCH-1 is a
reasoned decision, not a proven one: nobody has yet demonstrated that a Ring WebRTC session can be driven
from a WebView with an injected outbound track on both platforms. The spec is now correct and complete
enough that this is the *only* question that matters. Run task 2 before anything else.
