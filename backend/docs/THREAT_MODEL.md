# Threat model: Threshold backend

Written deliverable for task 27 (requirements FR-1.6, FR-1.7, FR-8.7, NFR-3).
The paired authorization and redaction test suite lives at
`backend/test/security/authorization.test.ts` and proves the controls below.

Source of truth for behavior: `.kiro/specs/threshold-doorbell/` (design.md §7).

## 1. Assets

| Asset | Sensitivity | Where it lives |
|---|---|---|
| Ring access and refresh tokens | High. Grant control of the doorbell. | Backend only, KMS-encrypted at rest in `ring_tokens`. Never on device. |
| Ring client secret and HMAC key | High. Application secrets. | AWS Secrets Manager. Never on device, never in logs. |
| App-to-backend session credential | Medium. Binds a resident. | Device secure store. Signed, 30 minute idle expiry. |
| Transcript text (visitor speech) | Personal data. | `conversations`, resident-scoped, 90 day TTL. |
| Resident identity (`residentSub`) | Personal data. | Derived from the session on every request. |

## 2. Trust boundaries

![Data and privacy model](../../docs/hackathon/diagrams/05-data-privacy-model.svg)

*The trust boundary in one view: the device never holds the Ring secret or tokens, and only text turns and control traffic cross to the backend and AWS.*

1. Device to backend: HTTPS/WSS, TLS 1.2+. The device is untrusted for
   authorization decisions. It presents only the session credential.
2. Backend to Ring: server-side OAuth. The client secret and tokens never cross
   to the device.
3. Backend to AWS (KMS, DynamoDB, Bedrock, Secrets Manager): least-privilege IAM
   per service.
4. Ring to backend (webhooks): authenticated by constant-time HMAC over the raw
   body.

## 3. STRIDE analysis and controls

### Spoofing
- **Threat.** A client forges a session or claims another resident's identity.
- **Control.** Sessions are HMAC-signed and verified in constant time
  (`security/session.ts`). `residentSub` is read from the verified session on
  every resident-scoped route, never from the request body or query (FR-8.7).
  A conflicting client-supplied `residentSub` is rejected 403 `resident_mismatch`
  (transcript create). Proven by the authorization suite.

### Tampering
- **Threat.** A forged or replayed Ring webhook injects events.
- **Control.** Constant-time HMAC-SHA256 over the raw body (`security/hmac.ts`);
  a mismatch returns 401 with the body neither parsed nor logged. Idempotency by
  `requestId` (conditional put) blocks replay from creating duplicate alerts
  (FR-3.1, 3.2).

### Repudiation
- **Threat.** Inability to correlate an action to a request.
- **Control.** Structured logs carry a correlation id (the request id, aligned to
  the Ring `requestId` at the webhook). Logs never contain PII, tokens, or
  bodies, so correlation is possible without exposure (design.md §10).

### Information disclosure
- **Threat.** Tokens, secrets, session credentials, or transcript text leak via
  responses or logs.
- **Controls.**
  - Ring tokens are KMS-encrypted at rest and are never returned in any response
    or written to the device (FR-1.6). The OAuth callback returns only a session
    cookie and a redirect; no Ring token appears in headers or body.
  - The logger uses a redaction allowlist (`observability/logger.ts`) covering
    tokens, `authorization`, `cookie`, secrets, `residentSub`, transcript `text`,
    `turns`, and request bodies (FR-1.7, NFR-3).
  - Error envelopes never include internals; unknown errors collapse to a generic
    `internal` message.

### Denial of service
- **Threat.** Ring rate limits are exceeded, or a dependency outage cascades.
- **Controls.** Token-bucket throttle never exceeds 100 rps (NFR-7); 429/5xx get
  bounded backoff with jitter then a typed error (`ring-gateway.ts`). Dependency
  failures degrade gracefully (fixed safe replies, cached devices, poll fallback)
  without crashing a session (NFR-5).

### Elevation of privilege
- **Threat.** A resident reads or deletes another resident's data.
- **Control.** Every store read/write is scoped by the session `residentSub`.
  Cross-resident reads return empty or 404; cross-resident writes are impossible
  because the server sets `residentSub`. Proven by the authorization suite.

## 4. Explicitly out of scope for v1

- No account system beyond Ring OAuth identity (N5).
- No visitor-facing surface; the visitor is never an authenticated principal (N9).
- `/signaling` is an accepted single point of failure for new sessions (D-5).

## 5. Controls-to-tests traceability

| Control | Test |
|---|---|
| `residentSub` server-derived; foreign rejected 403 | `authorization.test.ts` |
| Cross-resident read isolation | `authorization.test.ts` |
| No Ring token on device or in OAuth response | `authorization.test.ts`, `routes/oauth.test.ts` |
| Log redaction allowlist | `authorization.test.ts` |
| Constant-time HMAC, no body on bad signature | `routes/webhook.test.ts`, `security/hmac.test.ts` |
| Session expiry drives single recovery flow | `security/session.test.ts`, `routes/oauth.test.ts` |
