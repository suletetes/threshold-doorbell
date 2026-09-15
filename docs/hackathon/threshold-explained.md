# Threshold — A Plain-English Explainer

*For a teammate reading this cold. No prior context needed. If you only read one file, read this one,
then jump to `threshold-spec.md` for the engineering detail.*

---

## The one-sentence version

**We're building a video doorbell app for deaf and hard-of-hearing people that shows live captions of what
the visitor is saying, and lets the resident tap a reply that the doorbell then speaks out loud — a real
two-way conversation, no hearing required.**

It's an app for the **Amazon Developer Hackathon 2026**, built on the **Ring** track (Ring makes the video
doorbells), written in **Flutter**.

---

## The problem we're solving

Picture someone who is deaf. They own a Ring video doorbell — the normal kind millions of people have.
Someone rings it. Here's what happens today:

- Their phone buzzes. Good.
- They open the app and **see** a person standing at their door. Fine.
- The visitor starts **talking** — "I'll leave the parcel with your neighbour," "I need a signature,"
  "I'm here to read the meter."
- ...and the deaf person gets **none of it.** They can see a mouth moving. That's it.

So their choice is: ignore the door, or open it to a stranger and try to lip-read or mime. The doorbell
tells them **someone** is there. It has never once told them **what that person wants.**

### "Don't products for deaf people already exist?"

Yes — and this is the key insight. We looked at the whole market of "doorbells for the deaf." Every single
product solves the **same half** of the problem:

- Flashing lights
- Extra-loud chimes (up to ~100 decibels)
- Vibrating pagers and wristbands

Notice what they all do: they make the **alert** more noticeable. They shout *"SOMEONE IS AT THE DOOR!"*
louder and brighter.

**Not one of them handles the conversation.** Nobody solves *what is the person saying* and *how do I
answer them.* That gap — the conversation — is the entire opportunity. We're building the missing half.

### Who this helps

- **Deaf and hard-of-hearing people** — the primary users.
- **Older people** with age-related hearing loss (a doorstep-scam risk group — they can reply safely
  without opening the door).
- Scale: roughly **430 million people** worldwide have disabling hearing loss, and it's more than 1 in 4
  people over 60. And because it's a free app on a doorbell they already own, it works for people who can't
  afford specialist hardware.

---

## How Threshold works (the two magic moments)

There are exactly two things Threshold does that nothing else does. Understand these two and you understand
the whole product.

**Moment 1 — Visitor talks, words appear on the phone.**
The visitor's speech is captured, turned into text, and shown as **live captions** on the resident's phone,
in large, high-contrast, easy-to-read text.

**Moment 2 — Resident taps a reply, the doorbell says it out loud.**
The resident taps a suggested reply (like *"Please leave it at the door"*) or types their own. The app
turns that text into a **spoken voice** and plays it **out of the doorbell's speaker** — so the visitor
hears a normal-sounding answer.

Put them together and you get a full back-and-forth conversation with someone at the door, where the
resident never had to hear a thing.

```
Visitor speaks  →  doorbell  →  phone  →  speech-to-text  →  captions on screen
Resident taps a reply  →  text-to-speech  →  doorbell speaker  →  visitor hears it
```

---

## The clever technical insight (why this is even possible)

Here's the part that makes this a *smart* hackathon entry rather than an obvious one.

A Ring doorbell's audio actually works in **both directions** — the doorbell can send its microphone audio
to you, AND you can send audio back out to its speaker. (That's how "two-way talk" works on a normal Ring.)

When we read Amazon's own official example code for the Ring API, we found that their sample **only uses the
incoming direction** (visitor → you) and completely ignores the outgoing one. The channel to *send audio
back to the doorbell* is sitting there, switched on in the connection, and unused.

**Threshold is built on the exact channel that almost every other hackathon entry will leave idle.** That's
our unfair advantage: we're not inventing a new capability, we're using one that already exists but that
nobody bothers with — and pairing it with speech-to-text and text-to-speech to serve people the device
currently excludes.

---

## Key concepts / glossary

Terms that'll come up when we build this. Skim now, refer back later.

| Term | What it means in plain English |
|---|---|
| **Ring track** | The category of the hackathon where you build on Ring doorbells/cameras. Our chosen lane. |
| **Ring Partner API** | The official way Amazon lets outside developers connect to Ring devices — get events, live video, live audio. |
| **WebRTC** | The technology that carries live video and audio between the doorbell and our app in real time. |
| **`sendrecv` audio** | The setting that means audio flows *both ways*. This is the channel we exploit. |
| **Webhook** | A message Ring sends our server the instant something happens ("motion detected," "person detected"), including a thumbnail photo. It's how we know to alert the user. |
| **Speech-to-text (ASR / captions)** | Turning the visitor's spoken words into on-screen text. Two options: cloud (Amazon Transcribe) or on-device (Whisper). |
| **Amazon Transcribe** | Amazon's cloud service that turns speech into text in real time. Our **default** caption engine — reliable and it earns us an extra prize. |
| **On-device Whisper ("Privacy Mode")** | Running the speech-to-text *on the phone itself* so the audio never leaves the device. A privacy feature — our stretch goal. |
| **Text-to-speech (TTS)** | Turning the resident's typed/tapped reply into a spoken voice. This is what the doorbell says out loud. |
| **Amazon Bedrock** | Amazon's AI service. We use it only to suggest 3 quick reply options based on the conversation — nothing more. |
| **Haptics** | The phone's vibration. We use *distinct* buzz patterns (one for "person at door," another for "motion") so a deaf user can tell events apart without looking. |
| **WCAG 2.2 AA** | The accessibility standard (readable text, screen-reader support, contrast). Ring's own guidelines require it, and it's core to who we serve. |
| **Flutter** | The framework we're building the app in — one codebase runs on both iPhone and Android. |
| **The "spike"** | A small throwaway test we do *first* to prove the riskiest unknown works before we build anything real (see below). |

---

## What we are NOT building (so we don't over-scope)

Important, because it keeps us focused and avoids the "just another AI chatbot" trap:

- ❌ **Not a chatbot / voice assistant.** There's no AI personality, no open-ended chat. The AI only does
  three narrow jobs: hear→text, text→voice, and suggest 3 replies.
- ❌ **Not a security/surveillance product.** It's an accessibility and communication tool.
- ❌ **Not a hardware product.** No new gadgets. It's software on a doorbell people already own.
- ❌ **Not (for the hackathon) translation or sign-language recognition.** Cool ideas, explicitly parked as
  "nice-to-have" so they don't eat our time.

---

## The single biggest risk (everyone on the team should know this)

The hardest, least-certain part is **Moment 2** — actually getting a computer-generated voice to play out of
the doorbell's speaker through our Flutter app. The *incoming* half (captions) is well-understood. The
*outgoing* half is the unknown.

So the very first thing we do — before designing a single screen — is a **spike**: a tiny test that connects
to a doorbell and tries to send a synthesised voice out of it. If it works, great, we build the real thing.
If it doesn't, we switch to a known fallback (running that audio piece inside an in-app mini-browser) — and
we decide that in **week one**, not week five. Rule of thumb: never leave the scariest unknown for last.

---

## Why this can win

Judges score on four things. Threshold is strong on all four:

- **Technical merit** — uses the two-way audio channel nobody else touches, plus real Ring events, plus AWS.
- **Design** — a genuinely accessible, single-purpose app built for people the device currently ignores.
- **Impact** — hundreds of millions of potential users, a clear real-world need, works on hardware they own.
- **Quality of the idea** — it turns an audio-first device into a two-way *text* device for deaf users.
  That's a "why has nobody done this?" idea, not a "seen it before" one.

**In one line for the pitch:** *Ring already reached their door. Threshold makes it speak their language.*

---

*Next: read `threshold-spec.md` for the full architecture, feature list, 38-day plan, and demo script.
`research-and-scoring.md` has the evidence and how we compared this against 13 other ideas.*
