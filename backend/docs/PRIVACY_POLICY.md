# Threshold privacy policy

Written deliverable for task 30 (requirement FR-14.2). This is the plain
language privacy policy referenced in-product on first run and in Settings. It
states, without hedging, what Threshold does and does not do with what a visitor
says at the door.

Source of truth for behavior: `.kiro/specs/threshold-doorbell/` (requirements
FR-8, FR-14, NFR-4; design.md §7).

## Who is responsible

You, the resident who installs Threshold and owns the Ring doorbell, are the
data controller for the transcripts Threshold creates. Threshold is a tool you
operate. You are responsible for using it lawfully in your jurisdiction,
including any local requirement to inform visitors that they may be recorded or
transcribed (FR-14.2). Threshold provides an optional door notice to help you do
that (see "Recording notice" below).

## What Threshold transcribes

When you open a live session, Threshold turns what your visitor says into text so
you can read it. That is the whole point of the product: a two-way conversation
for a resident who cannot hear.

## What Threshold stores

- Threshold stores the conversation as **text only**: ordered turns with a
  timestamp, the speaker label, the source, a confidence value, and a
  provisional flag (FR-8.1).
- Threshold **never stores raw audio or video**, at any time, in any mode
  (FR-8.3, NFR-4). There is no audio or video artifact on the device or the
  backend to leak, subpoena, or breach.
- Transcripts are kept for **90 days by default**, then deleted automatically.
  The retention period is shown in Settings (FR-8.5).

## Clarity Mode and Privacy Mode

Threshold has two caption modes, and they differ in where transcription happens.

- **Clarity Mode** (default): inbound audio is relayed to Amazon Transcribe for
  streaming speech-to-text, and finalized caption text may be sent to Amazon
  Bedrock to suggest up to three short replies. Only **text** is sent to Bedrock,
  never audio or video (FR-7.4). This mode is more accurate and supports more
  languages.
- **Privacy Mode**: inbound audio is transcribed **entirely on your device**.
  Neither the audio nor the transcript text leaves the handset (FR-5.2, NFR-4).
  Bedrock is not called; reply suggestions are produced on-device (FR-7.1a).
  Settings states this difference plainly. Privacy Mode requires a one-time
  on-device model download, which happens only after you opt in and never during
  a live session (FR-5.2a).

In every mode, the doorstep audio itself is never persisted.

## What leaves your device

![Data and privacy model](../../docs/hackathon/diagrams/05-data-privacy-model.svg)

*What leaves the device and what stays on it: Clarity Mode relays audio to the cloud for captions and replies, Privacy Mode keeps audio and text on the phone, and only text turns are ever persisted.*

- Your Ring access and refresh tokens are held **only on the backend**,
  encrypted with AWS KMS. They are **never stored on your device** (FR-1.6). Your
  device holds only a short-lived session credential.
- In Clarity Mode, inbound audio streams to Amazon Transcribe over an encrypted
  connection for captioning, and finalized text may go to Amazon Bedrock for
  suggestions. Nothing derived from audio is stored by those services on your
  behalf beyond the request.
- In Privacy Mode, nothing derived from audio leaves your device.

## Recording notice

Threshold shows a one-time notice on first use, and again in Settings, that it
transcribes what visitors say, and requires you to acknowledge it (FR-14.1). You
can enable an optional, off-by-default audible notice played at the door at the
start of a session (FR-14.3). If spoken replies are unavailable on your device
and you have enabled the audible notice, Threshold will not silently transcribe:
it offers you the choice to continue with captions without the audible notice, or
to disable transcription for that session, and it remembers your choice
(FR-14.3a).

## Your controls

- **Delete a transcript**: removes it from your device and the backend in the
  same operation, with confirmation (FR-8.4).
- **Delete all my data**: erases every transcript for you from the device and the
  backend and revokes your stored Ring tokens, behind a confirmation step
  (FR-8.6).
- **Retention**: transcripts older than 90 days are deleted automatically
  (FR-8.5); the period is visible in Settings.

## Security summary

- No raw audio or video is ever persisted (FR-8.3, NFR-4).
- Ring tokens are KMS-encrypted at rest and never placed on the device (FR-1.6).
- All transport uses TLS 1.2 or higher; webhook signatures are verified in
  constant time (NFR-3).
- Logs never contain tokens, session credentials, transcript text, personal
  identifiers, or request bodies (FR-1.7, NFR-3).

## Contact

Threshold is an Amazon Developer Hackathon 2026 project. For data questions about
a specific deployment, contact the resident who operates that installation, who
is the data controller described above.
