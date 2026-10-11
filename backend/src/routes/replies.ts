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

// M-2: bound the free-text field well below the 64 KiB global body limit so a
// single legitimate request cannot carry an oversized string into the Bedrock
// prompt path. A visitor utterance is at most a sentence or two; 4096 chars is a
// generous ceiling. Over-limit input returns the uniform 400 'schema' envelope.
const MAX_VISITOR_TEXT_CHARS = 4096;

export async function registerReplyRoutes(app: FastifyInstance): Promise<void> {
  const service = new ReplyService(app.container.bedrock);

  app.post(
    '/replies',
    { preHandler: app.requireSession },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const body = (request.body ?? {}) as ReplyBody;

      const visitorText = typeof body.visitorText === 'string' ? body.visitorText : '';
      const language = typeof body.language === 'string' && body.language !== '' ? body.language : 'en-US';

      // FR-7.4: reject anything that is not text (defensive; the schema only
      // accepts text fields, but a caller must never smuggle binary here).
      if (body.visitorText !== undefined && typeof body.visitorText !== 'string') {
        throw errors.schema('visitorText must be a string.');
      }
      // M-2: reject an over-long visitorText rather than forward it to Bedrock.
      if (visitorText.length > MAX_VISITOR_TEXT_CHARS) {
        throw errors.schema('visitorText is too long.');
      }

      // MED-24: Privacy Mode must FAIL CLOSED. Accept exactly 'clarity' or
      // 'privacy'; a missing mode defaults to the safe choice (privacy); any
      // other value (for example 'Privacy', 'PRIVACY', 'private') is a 400
      // rather than silently falling through to Clarity Mode and sending
      // visitor speech to Bedrock while the user believes Privacy Mode is on.
      let mode: 'clarity' | 'privacy';
      if (body.mode === undefined || body.mode === null) {
        mode = 'privacy';
      } else if (body.mode === 'clarity' || body.mode === 'privacy') {
        mode = body.mode;
      } else {
        throw errors.schema("mode must be 'clarity' or 'privacy'.");
      }

      // FR-7.1a: Privacy Mode never calls Bedrock and never sends text off-device.
      // The server returns only the fixed safe set; the app augments locally.
      if (mode === 'privacy') {
        reply.code(200).send({ suggestions: fixedSet() });
        return;
      }

      const result = await service.suggest({ visitorText, language });
      if (result.fallback) {
        // design.md §10 metric: Bedrock fallback rate.
        app.container.metrics.increment('bedrock_fallback');
      }
      reply.code(200).send({ suggestions: result.suggestions });
    },
  );
}
