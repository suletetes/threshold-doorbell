// POST /replies (Task 10, FR-7.1, 7.3, 7.4, 7.1a). Session-scoped. Returns at
// most 3 suggestions. Bedrock is invoked only in Clarity Mode; a Privacy-Mode
// request never reaches Bedrock and gets the fixed safe set (FR-7.1a). On a 2 s
// timeout or Bedrock error the fixed safe set is returned with a 200 so the
// reply bar is never empty (FR-7.3, 7.5). Text only (FR-7.4).

import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { errors } from '../domain/errors.js';
import { fixedSet, ReplyService } from '../services/reply-service.js';

interface ReplyBody {
  visitorText?: unknown;
  language?: unknown;
  mode?: unknown; // 'clarity' | 'privacy'
}

export async function registerReplyRoutes(app: FastifyInstance): Promise<void> {
  const service = new ReplyService(app.container.bedrock);

  app.post(
    '/replies',
    { preHandler: app.requireSession },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const body = (request.body ?? {}) as ReplyBody;

      const visitorText = typeof body.visitorText === 'string' ? body.visitorText : '';
      const language = typeof body.language === 'string' && body.language !== '' ? body.language : 'en-US';
      const mode = body.mode === 'privacy' ? 'privacy' : 'clarity';

      // FR-7.4: reject anything that is not text (defensive; the schema only
      // accepts text fields, but a caller must never smuggle binary here).
      if (body.visitorText !== undefined && typeof body.visitorText !== 'string') {
        throw errors.schema('visitorText must be a string.');
      }

      // FR-7.1a: Privacy Mode never calls Bedrock and never sends text off-device.
      // The server returns only the fixed safe set; the app augments locally.
      if (mode === 'privacy') {
        reply.code(200).send({ suggestions: fixedSet() });
        return;
      }

      const result = await service.suggest({ visitorText, language });
      reply.code(200).send({ suggestions: result.suggestions });
    },
  );
}
