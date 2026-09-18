// Transcript routes (Task 9, FR-8.1..8.7, AT-15, AT-19). All session-scoped and
// residentSub server-derived. List is paginated, searchable, and date-filtered.
// /me/data erases all transcripts and revokes tokens (FR-8.6).

import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { errors } from '../domain/errors.js';
import type { Conversation, Page } from '../domain/types.js';
import { decodeCursor, normalizeLimit, paginate } from '../domain/pagination.js';
import { TranscriptService } from '../services/transcript-service.js';

interface ListQuery {
  query?: string;
  from?: string;
  to?: string;
  limit?: string;
  cursor?: string;
}

export async function registerTranscriptRoutes(app: FastifyInstance): Promise<void> {
  const service = new TranscriptService(
    app.container.conversationStore,
    app.container.tokenStore,
  );

  // GET /transcripts -> paginated, searchable, date-filtered list.
  app.get<{ Querystring: ListQuery }>(
    '/transcripts',
    { preHandler: app.requireSession },
    async (
      request: FastifyRequest<{ Querystring: ListQuery }>,
      reply: FastifyReply,
    ): Promise<Page<Conversation>> => {
      const residentSub = request.session!.sub;
      const limit = normalizeLimit(request.query.limit);
      const offset = decodeCursor(request.query.cursor);
      if (offset === null) throw errors.schema('Invalid cursor.');

      const all = await service.list(residentSub, {
        query: request.query.query,
        from: request.query.from,
        to: request.query.to,
      });
      // Defensive TTL filter (FR-8.5): never surface an expired transcript even
      // if the store's TTL sweep has not yet run.
      const live = all.filter((c) => !TranscriptService.isExpired(c));
      const page = paginate(live, limit, offset);
      reply.code(200).send(page);
      return page;
    },
  );

  // POST /transcripts -> create; server sets residentSub; foreign value 403.
  app.post(
    '/transcripts',
    { preHandler: app.requireSession },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const residentSub = request.session!.sub;
      const conversationId = await service.create(
        (request.body ?? {}) as Record<string, unknown>,
        residentSub,
      );
      reply.code(201).send({ conversationId });
    },
  );

  // DELETE /transcripts/:id -> 204, or 404 when not found for this resident.
  app.delete<{ Params: { id: string } }>(
    '/transcripts/:id',
    { preHandler: app.requireSession },
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const residentSub = request.session!.sub;
      const removed = await service.delete(residentSub, request.params.id);
      if (!removed) throw errors.notFound('Transcript not found.');
      reply.code(204).send();
    },
  );

  // DELETE /me/data -> erase all transcripts + revoke tokens (FR-8.6).
  app.delete(
    '/me/data',
    { preHandler: app.requireSession },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const residentSub = request.session!.sub;
      await service.eraseAll(residentSub);
      reply.code(204).send();
    },
  );
}
