// GET /devices (Task 6, FR-2.1, FR-2.2, FR-2.3, FR-17, NFR-7). Session-scoped.
// Fetches authorized Ring devices through the schema-validating adapter and the
// throttled gateway, paginated with the standard { items, nextCursor } envelope.
// Errors follow the design.md §4 table: 401, 429 rate_limited, 502
// ring_unavailable, 502 ring_contract_invalid. An account with zero devices
// returns an empty page (the app renders the FR-2.2 empty state).

import type { FastifyInstance, FastifyRequest } from 'fastify';
import { errors } from '../domain/errors.js';
import type { Device, Page } from '../domain/types.js';
import { decodeCursor, normalizeLimit, paginate } from '../domain/pagination.js';

interface ListQuery {
  limit?: string;
  cursor?: string;
}

export async function registerDeviceRoutes(app: FastifyInstance): Promise<void> {
  app.get<{ Querystring: ListQuery }>(
    '/devices',
    { preHandler: app.requireSession },
    async (request: FastifyRequest<{ Querystring: ListQuery }>): Promise<Page<Device>> => {
      const residentSub = request.session!.sub;
      const limit = normalizeLimit(request.query.limit);
      const offset = decodeCursor(request.query.cursor);
      if (offset === null) throw errors.schema('Invalid cursor.');

      // withAccessToken adds refresh-once-on-401 (FR-1.4); the gateway adds the
      // token-bucket throttle and 429/5xx backoff (FR-2.3). A schema drift
      // surfaces as ring_contract_invalid (FR-17) and is returned as 502.
      const devices = await app.container.ringTokens.withAccessToken(residentSub, (token) =>
        app.container.ringGateway.listDevices(residentSub, token),
      );

      // Record the device->account mapping so inbound webhooks can be attributed
      // to the owning resident instead of a hard-coded account (CRIT-04).
      await app.container.deviceAccountStore.mapAll(
        devices.map((d) => d.id),
        residentSub,
      );

      // LOW-28: give the list a stable total order (by device id) before
      // slicing by the offset cursor. Ring returns the devices in an unspecified
      // order, so without this an offset cursor could point at a different
      // device between pages and silently skip or duplicate rows.
      // NIT-05: return the page (default 200) rather than send() and return.
      const ordered = [...devices].sort((a, b) => a.id.localeCompare(b.id));
      return paginate(ordered, limit, offset);
    },
  );
}
