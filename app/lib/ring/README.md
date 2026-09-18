# ring/

Ring Partner API integration.

- **OAuth 2.0** account linking + token refresh (base URL `https://api.amazonvision.com`, JSON:API).
- **WebRTC session** mirroring the sample's `useWebRTCStream.ts`: audio transceiver `sendrecv`,
  video `recvonly`. STUN via `stun:stun.l.google.com:19302`.
- **Device discovery / capabilities / privacy zones.**
- Respect the 100 req/s rate limit (exponential backoff) and the mandatory media watermark
  (keep overlays out of the top corners).

Webhook receipt (`motion_detected`, `person_detected` with `confidence` / `bounding_box` /
`thumbnail_url`) lives on the backend, which pushes to this app.
