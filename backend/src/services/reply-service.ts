// Smart Replies service (Task 10, FR-7). Clarity Mode only: requests at most 3
// short suggestions from Bedrock with a hard 2 s timeout; on timeout or error it
// falls back to the fixed safe set so the reply bar is never empty (FR-7.3, 7.5).
// Never invoked for Privacy-Mode sessions (FR-7.1a). Text only; the caller must
// never pass audio/video (FR-7.4). All suggestions are dash-stripped (NFR-10).

import type { BedrockPort, SmartReplyRequest } from './bedrock.js';
import { FIXED_SAFE_REPLIES } from '../domain/types.js';
import { stripDashes } from '../domain/ui-copy.js';

export const REPLY_TIMEOUT_MS = 2000; // FR-7.3
export const MAX_SUGGESTIONS = 3; // FR-7.1

export interface SmartReplyResult {
  suggestions: string[];
  /** true when the fixed safe set was used (Bedrock timed out or errored). */
  fallback: boolean;
}

export class ReplyService {
  constructor(
    private readonly bedrock: BedrockPort,
    private readonly timeoutMs = REPLY_TIMEOUT_MS,
  ) {}

  /**
   * Produce up to 3 suggestions for a Clarity-Mode session. This method must not
   * be called for Privacy Mode; the route enforces that (FR-7.1a). On any Bedrock
   * failure or a timeout beyond timeoutMs, returns the fixed safe set.
   */
  async suggest(request: SmartReplyRequest): Promise<SmartReplyResult> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const raw = await this.bedrock.suggest(request, controller.signal);
      const cleaned = sanitize(raw);
      if (cleaned.length === 0) {
        return { suggestions: fixedSet(), fallback: true };
      }
      return { suggestions: cleaned, fallback: false };
    } catch {
      // Timeout or Bedrock error: never block the reply bar (FR-7.3, 7.5).
      return { suggestions: fixedSet(), fallback: true };
    } finally {
      clearTimeout(timer);
    }
  }
}

/** The fixed safe set, dash-stripped for display safety (FR-7.2, NFR-10). */
export function fixedSet(): string[] {
  return FIXED_SAFE_REPLIES.map(stripDashes);
}

/**
 * Normalize model output: trim, drop empties, strip dashes (NFR-10), dedupe,
 * and cap at 3 (FR-7.1). Non-string entries are ignored defensively.
 */
function sanitize(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  const seen = new Set<string>();
  const out: string[] = [];
  for (const item of raw) {
    if (typeof item !== 'string') continue;
    const cleaned = stripDashes(item);
    if (cleaned === '' || seen.has(cleaned)) continue;
    seen.add(cleaned);
    out.push(cleaned);
    if (out.length >= MAX_SUGGESTIONS) break;
  }
  return out;
}
