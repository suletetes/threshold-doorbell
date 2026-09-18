// Smart Replies port (Task 10, FR-7). Real adapter calls Amazon Bedrock; fixture
// returns deterministic suggestions. Text only, never audio/video (FR-7.4).

export interface SmartReplyRequest {
  /** Finalized visitor caption text. Text only (FR-7.1, FR-7.4). */
  visitorText: string;
  /** BCP-47 language of the conversation. */
  language: string;
}

export interface BedrockPort {
  /**
   * Return at most 3 short contextual suggestions. Implementations should honor
   * a hard timeout; on timeout or error the caller falls back to the fixed safe
   * set (FR-7.3). This method may reject; the caller handles fallback.
   */
  suggest(request: SmartReplyRequest, signal: AbortSignal): Promise<string[]>;
}
