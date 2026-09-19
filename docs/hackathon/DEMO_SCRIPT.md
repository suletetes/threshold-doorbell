# Threshold - demo run-of-show (3 minutes or under)

Problem first. Lead with the deaf-user problem in the first 45 seconds, hit the
two-way conversation as the aha inside 90 seconds, then close on depth and
impact. Judges are not required to watch past 3:00, so nothing essential lives
after the two-minute mark.

Format below: **Time** | on-screen action | spoken voiceover. Voiceover lines
are written to be read at a natural pace and fit their slot. Total target 2:55.

---

## 0:00 to 0:45 - The problem

**On screen:** Open on a real Ring alert. A man stands at the door. Show the
phone: the resident can see him, tap through, and that is where it stops. Then a
fast montage of the existing market: a strobe light, a flashing chime, a
vibrating pager.

**VO:**
"This is Priya. She is profoundly deaf, she lives alone, and she already owns a
Ring doorbell. It does exactly what it was built to do: it tells her someone is
here. But this man is asking something. Which flat. Whether to leave the parcel.
Whether she needs to sign. And she has no way to know."

"Every product built for deaf residents solves the same half of this. Flashing
lights. Louder chimes. Buzzers. They all shout louder that someone is at the
door. Not one of them tells her what they want."

---

## 0:45 to 0:55 - The turn

**On screen:** Cut to the Threshold app icon, then the live app.

**VO:**
"Threshold is the other half. It is the doorbell that talks back."

---

## 0:55 to 2:05 - The aha, live

**On screen, in order, on a real handset:**

1. Doorbell press. The phone fires its distinct person-at-door haptic pattern
   and shows the visitor thumbnail full-bleed. (Let the buzz be visible.)
2. Tap **Open**. The live view comes up, video on top, captions dominating the
   rest.
3. The visitor speaks. Captions stream in large and high-contrast, with a couple
   of low-confidence words visibly dimmed.
4. Three smart replies appear. Tap **"Please leave it at the door."**
5. The reply bar shows "speaking at your door" and the doorbell speaks the reply
   aloud. The visitor answers, and captions continue.
6. Flip the **Privacy Mode** toggle, cut the network, and show captions still
   streaming on-device.

**VO:**
"A visitor arrives. Her phone does not chime, it buzzes with a pattern she knows
means a person is at the door, and shows her who it is."

"She opens the live view. He speaks, and she reads it, in real time, with the
uncertain words marked uncertain so a guess is never dressed up as fact."

"She taps a reply. On-device speech turns it into audio, sends it up through the
doorbell, and he hears it out loud. He answers. She reads that too. That is a
complete two-way conversation, and no one had to hear a thing."

"And if she does not want a word of it leaving her phone, Privacy Mode runs the
entire speech pipeline on the handset. Watch: network off, still captioning."

---

## 2:05 to 2:40 - Depth

**On screen:** One clean architecture card (Ring `sendrecv` audio to Amazon
Transcribe to Amazon Bedrock, all in a Flutter app), then the searchable
transcript history screen with past door conversations. Briefly show the large
text and contrast controls.

**VO:**
"Under it: Ring's audio channel is already two-way, so we use the half everyone
else leaves idle. Visitor speech goes through Amazon Transcribe streaming for
live captions, or on-device Whisper in Privacy Mode. Amazon Bedrock writes the
reply suggestions. All of it in one Flutter app, built to WCAG 2.2 Double A."

"And every conversation is saved, so for the first time there is a searchable
record of what people actually said at your door."

---

## 2:40 to 3:00 - Impact close

**On screen:** Back to Priya's face at the resolved conversation, then a simple
impact card with the figures.

**VO:**
"Around 430 million people live with disabling hearing loss. More than a quarter
of everyone over 60. And nearly 80% of them are in low- and middle-income
countries, where a free app on a doorbell they already own beats buying
specialist hardware they cannot."

"Ring already reached their door. Threshold makes it speak their language."

---

## Presenter notes

- If the live audio-injection path is risky on the day, the WebView pipeline is
  the demo path; have the pre-recorded backup of the doorbell speaking cued so
  the aha beat is never mimed or skipped.
- Do not pitch this as captioning. If a judge could get the same result by
  pointing Google Live Transcribe at the door, the framing is wrong. Lead every
  time with the resident replying and the doorbell speaking.
- Keep overlays out of the top corners so nothing collides with Ring's mandatory
  watermark.
- If asked "why not Live Transcribe": it captions the room you are standing in,
  it is one-way, and it has no doorbell context. Threshold is two-way and
  doorbell-native. One sentence, then move on.
