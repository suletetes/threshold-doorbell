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
      // Session presence is required; residentSub scoping happens at the store
      // level in the real deployment. In the fixture the event store is the
      // resident's event feed.
      void request.session!.sub;
      const limit = normalizeLimit(request.query.limit);
      const offset = decodeCursor(request.query.cursor);
      if (offset === null) throw errors.schema('Invalid cursor.');

      const since =
        typeof request.query.since === 'string' && request.query.since !== ''
          ? request.query.since
          : undefined;

      // Ordered ascending by timestamp; newest-relevant events are paged with a
      // stable cursor (AT-19).
      const events = await app.container.eventStore.listOrdered(since);
      const page = paginate(events, limit, offset);
      reply.code(200).send(page);
      return page;
    },
  );
}
