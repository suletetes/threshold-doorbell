# captions/

Speech-to-text of the visitor's audio → the caption stream shown on screen.

- **Clarity Mode (default):** Amazon Transcribe streaming over WebSocket, with partial-results
  stabilization. Reliable, and it anchors the AWS Builder mini-challenge.
- **Privacy Mode (stretch goal):** on-device Whisper (`whisper_ggml` or FFI to whisper.cpp) so audio
  never leaves the handset. Add after Clarity Mode works.

Render partial results live; style low-confidence words as visibly uncertain - never present a guess as
certain (safety: a stranger is at the door).
