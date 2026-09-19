// GET /events (Task 6, FR-3.5). Session-scoped, paginated foreground poll of
// recent events used when push delivery fails or notifications are disabled.
// Supports ?since (ISO lower bound), ?limit, ?cursor with the standard envelope.

import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { errors } from '../domain/errors.js';
import type { DoorEvent, Page } from '../domain/types.js';
import { decodeCursor, normalizeLimit, paginate } from '../domain/pagination.js';

interface ListQuery {
  since?: string;
  limit?: string;
  cursor?: string;
}

export async function registerEventRoutes(app: FastifyInstance): Promise<void> {
  app.get<{ Querystring: ListQuery }>(
    '/events',
    { preHandler: app.requireSession },
    async (
      request: FastifyRequest<{ Querystring: ListQuery }>,
      reply: FastifyReply,
    ): Promise<Page<DoorEvent>> => {
      // residentSub is server-derived from the verified session and threaded
      // into the store read so a caller only ever sees their own events
      // (FR-8.7, AT-19). A foreign resident's events are never returned.
      const residentSub = request.session!.sub;
      const limit = normalizeLimit(request.query.limit);
      const offset = decodeCursor(request.query.cursor);
      if (offset === null) throw errors.schema('Invalid cursor.');

      const since =
        typeof request.query.since === 'string' && request.query.since !== ''
          ? request.query.since
          : undefined;

      // Ordered ascending by timestamp; newest-relevant events are paged with a
      // stable cursor (AT-19). Scoped to this resident.
      const events = await app.container.eventStore.listOrdered(residentSub, since);
      const page = paginate(events, limit, offset);
      reply.code(200).send(page);
      return page;
    },
  );
}
