// Webhook route (Task 5, FR-3.1, FR-3.2, NFR-6). Constant-time HMAC over the raw
// body; conditional-put idempotency by requestId; acknowledge 200 within 5 s
// then enqueue push asynchronously. On bad signature: 401, body not processed or
// logged. Duplicate requestId returns 200 and is processed at most once.

import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { errors } from '../domain/errors.js';
import { verifyTimestampedSignature } from '../security/hmac.js';
import { allowsDemoBypass } from '../config.js';
import { parseWebhook, WebhookService } from '../services/webhook-service.js';
import { getLogger } from '../observability/logger.js';

const SIGNATURE_HEADER = 'x-ring-signature';
const TIMESTAMP_HEADER = 'x-ring-timestamp';

export async function registerWebhookRoutes(app: FastifyInstance): Promise<void> {
  const { config } = app.container;
  const log = getLogger();

  // Capture the raw body for HMAC verification. This parser is registered on an
  // encapsulated child instance (see registerWebhookRoutes usage) so it does NOT
  // override JSON parsing for the rest of the app; only /webhook sees the raw
  // string body.
  app.addContentTypeParser(
    'application/json',
    { parseAs: 'string' },
    (_req, body, done) => {
      // Store the raw string; JSON.parse happens in the handler after HMAC.
      done(null, body);
    },
  );

  const service = new WebhookService(
    app.container.eventStore,
    app.container.push,
    // Resolve the resident for a device from the server-side device->account
    // mapping, never from a hard-coded account and never from the webhook body
    // (CRIT-04, FR-8.7). An unmapped device resolves to null so its event is
    // quarantined rather than attributed to any real resident.
    (deviceId: string) => app.container.deviceAccountStore.resolve(deviceId),
  );

  app.post('/webhook', async (request: FastifyRequest, reply: FastifyReply) => {
    // M-6: measure the webhook acknowledgement time (design.md section 10). The
    // 200 ack is sent before the fire-and-forget push, so we measure to the ack
    // (the SLA-relevant latency), not to the async delivery. Record it on the
    // happy path right before the ack is sent; a 401/400 short-circuits earlier
    // and is not an "acknowledged" delivery, so it is intentionally not timed.
    const ackStart = performance.now();
    const rawBody = typeof request.body === 'string' ? request.body : '';
    const signature = request.headers[SIGNATURE_HEADER] as string | undefined;
    const timestamp = request.headers[TIMESTAMP_HEADER] as string | undefined;

    // FR-3.1, MED-38: constant-time HMAC over `timestamp.body` against any
    // accepted key, within a +/-5 minute replay window. A mismatch, a missing
    // or stale timestamp, or an unknown key -> 401, with no body logging and no
    // processing.
    //
    // L-3: this encodes an ASSUMED signing contract that MUST be validated
    // against Ring's actual Partner webhook spec before go-live:
    //   - an x-ring-timestamp header is present on every delivery,
    //   - the HMAC is computed over the exact material `${timestamp}.${body}`,
    //   - the delivery is valid only within a +/-5 minute window.
    // If Ring's real deliveries differ (no timestamp header, a different signed
    // material, or a different window), EVERY real delivery would 401 here. When
    // the real format is confirmed, update verifyTimestampedSignature in
    // security/hmac.ts to match. The body-only verifySignature scheme in hmac.ts
    // remains available as the fallback if Ring signs the raw body alone.
    if (
      !verifyTimestampedSignature({
        timestamp,
        rawBody,
        providedSignature: signature,
        keys: config.webhookHmacKeys,
        allowDemoSignature: allowsDemoBypass(config.env),
      })
    ) {
      throw errors.badSignature();
    }

    // Parse only after the signature is trusted.
    let parsed: unknown;
    try {
      parsed = JSON.parse(rawBody);
    } catch {
      throw errors.schema('Webhook body was not valid JSON.');
    }
    const event = parseWebhook(parsed);

    // Idempotent conditional put by requestId (FR-3.2). Cheap; inside the budget.
    const outcome = await service.record(event);

    // M-6: record the ack latency just before sending the 200.
    app.container.metrics.observe('webhook_ack_ms', performance.now() - ackStart);

    // Acknowledge 200 FIRST (design.md §4). Push is enqueued asynchronously so
    // the 5 s budget is never at risk, and only for first deliveries.
    reply.code(200).send({ ok: true });

    if (outcome.firstDelivery) {
      // Fire-and-forget; never blocks the ack. Failures are surfaced via the
      // FR-3.5 poll, never thrown into the request path.
      void service
        .enqueuePush(outcome.event)
        .then((delivered) => {
          if (!delivered) {
            log.warn(
              { requestId: outcome.event.requestId, deviceId: outcome.event.deviceId },
              'push not delivered; app will fall back to foreground poll',
            );
          }
        })
        .catch((err) => {
          log.error({ err, requestId: outcome.event.requestId }, 'push enqueue failed');
        });
    }
  });
}
