# Operations runbook: Threshold backend

Written deliverable for task 30. Operational procedures for running the
Threshold backend in staging and production: token rotation, KMS key management,
and alarm response. It pairs with the threat model
(`backend/docs/THREAT_MODEL.md`) and the design (`.kiro/specs/threshold-doorbell/
design.md` §7, §10, §11).

## 1. Architecture recap for operators

- Stateless Fastify service, at least 2 instances, behind TLS (design.md §11).
  All state is in DynamoDB; any instance can serve any request.
- Application secrets (Ring client secret, webhook HMAC key, KMS key id) live in
  AWS Secrets Manager. Per-user Ring tokens do NOT live in Secrets Manager; they
  are KMS-encrypted attributes in the `ring_tokens` DynamoDB table (design.md §2,
  D-7).
- `/signaling` is a single point of failure by design: no backend means no new
  sessions (design.md §1, FR-15.4). This is surfaced to residents, not silently
  swallowed.

## 2. Token rotation

### 2.1 Ring per-user access and refresh tokens

- Access tokens are refreshed automatically: when a token is within 120 s of
  expiry or a Ring call returns 401, the service refreshes once and retries the
  original call once (FR-1.4). Operators do not rotate these by hand.
- Rotation is observable via the `refresh` metric (design.md §10). A sudden
  spike in refreshes can indicate Ring-side token invalidation; investigate Ring
  status before assuming a bug.
- To revoke a single resident's tokens, use the erasure path: `DELETE /me/data`
  for that resident deletes their transcripts and the `ring_tokens` row in one
  transaction (FR-8.6). There is no separate "revoke tokens only" endpoint by
  design; revocation is part of data erasure.

### 2.2 Application secrets (Secrets Manager)

Rotate on a fixed schedule and immediately on any suspected exposure:

1. **Webhook HMAC key**: create the new key version in Secrets Manager. Deploy
   instances that accept BOTH the current and previous key for a short overlap
   window (dual-verify), then coordinate the key change with Ring, then remove
   the old key. Never log the key (NFR-3). Constant-time verification is already
   enforced in `src/security/hmac.ts`.
2. **Ring client secret**: rotate in the Ring developer console, update the
   Secrets Manager value, and roll instances. The secret never reaches the
   device (FR-1.2), so no app release is needed.
3. **Session signing secret**: rotating it invalidates all live app sessions.
   Residents transparently re-authenticate through the single unified recovery
   flow (FR-1.5). Schedule during low traffic.

## 3. KMS key management

- One KMS key (alias configured via `KMS_KEY_ID`, default
  `alias/threshold-ring-tokens`) encrypts the Ring token attributes at rest
  (design.md §2, D-7).
- **Least privilege**: only the backend task role may call `Encrypt` and
  `Decrypt` with this key. No human role should have `Decrypt` in production.
- **Key rotation**: enable automatic annual KMS key rotation. Because DynamoDB
  stores ciphertext that references the key, existing rows keep decrypting with
  the rotated key material transparently; no re-encryption job is required for
  automatic rotation.
- **Manual re-key** (only if the key must be replaced, not rotated): stand up the
  new key, run a one-off job that reads each `ring_tokens` row, decrypts with the
  old key, re-encrypts with the new key, and writes back, then retire the old
  key. Run it as the backend role, never exporting plaintext outside the process.
- **Compromise**: if key compromise is suspected, disable the key (which halts
  session starts, since tokens cannot be decrypted), rotate the client secret,
  force resident re-authentication, and re-key as above.

## 4. Alarms and response

Alarms follow design.md §10. For each, the response keeps sessions alive where
the design allows graceful degradation (NFR-5).

| Alarm | Trigger | First response |
|---|---|---|
| Webhook ack over 5 s | `webhook_ack_ms` p95 exceeds 5000 ms | Webhooks must ack 200 within 5 s (FR-3.1). Check push enqueue latency; the 200 is sent BEFORE push work, so investigate the handler and DynamoDB conditional-put latency. Duplicate `requestId` returns 200 immediately and must not count as work. |
| Transcribe error rate high | rising `4500` closes on `/asr/stream` | Captions degrade with an explicit notice; the caption mode is never switched mid-session (FR-10.1, design.md §6). Check AWS Transcribe status and the ASR relay logs (correlated by requestId). Sessions do not crash. |
| 429 rate to Ring | approaching the 100 rps ceiling | Token-bucket throttle plus backoff with jitter is already applied (NFR-7). Confirm no runaway retry loop; check for a hot device polling. |
| Probe success rate low | `probe_success` / (`probe_success` + `probe_failure`) falls below threshold | More sessions are landing in Captions-Only (FR-6.4a). Correlate with app or platform changes. This degrades gracefully, so it is a quality alarm, not an outage. |
| Schema validation failures | rising `schema_validation_failure` | Likely Ring contract drift (FR-17). The affected feature degrades to `ring_contract_invalid` without crashing; capture the diagnostic and update the Ring adapter schema. |
| Bedrock fallback rate high | rising `bedrock_fallback` | Reply bar still works with the fixed safe set (FR-7.3, 7.5); no user-facing outage. Check Bedrock status and the 2 s timeout budget. |
| Backend unreachable | health check failing across instances | New sessions are unavailable and the app states so (FR-15.4). Cached history stays usable on devices. Restore instances; no data loss because state is in DynamoDB. |

## 5. Observability quick reference

- Logs: structured JSON (pino), correlation id equal to the Ring `requestId`
  where present, otherwise the Fastify request id (design.md §10). A redaction
  allowlist removes tokens, PII, transcript text, and bodies (NFR-3); proven by
  `backend/test/observability/logger.test.ts`.
- Metrics: latency (G1a, G1b, G2, G3, webhook ack) and counters (probe
  success/failure, Captions-Only vs two-way share, injection failure, Bedrock
  fallback, refresh, schema validation failures). See
  `src/observability/metrics.ts`.

## 6. Deploy and rollback

- CI gates (typecheck, lint, vitest, flutter test, UI-copy lint) must pass before
  merge; CI config is never pushed directly to `main` (design.md §11). See
  `.github/workflows/ci.yml`.
- Deploy on merge to `main` after gates pass. Because the service is stateless,
  rollback is a redeploy of the previous image; no data migration is involved for
  a rollback.
