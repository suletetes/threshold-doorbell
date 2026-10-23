/**
 * Real Amazon Bedrock adapter — smart reply suggestions via Nova Micro.
 *
 * Implements BedrockPort (bedrock.ts) using @aws-sdk/client-bedrock-runtime.
 * Uses amazon.nova-micro-v1:0 — confirmed available on this account in us-east-1
 * (AWS-native, no third-party EULA gate, 7-9× cheaper than Claude Haiku).
 *
 * INSTALL (from backend/):
 *   npm install @aws-sdk/client-bedrock-runtime
 *
 * WIRE IT IN (backend/src/container.ts):
 *   import { RealBedrock } from './services/real-bedrock.js';
 *   // In buildContainer, replace the FixtureBedrock line:
 *   const bedrock = overrides.bedrock ?? new RealBedrock();
 *
 * CREDENTIALS:
 *   The SDK uses the standard AWS credential chain:
 *   1. Environment variables  AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
 *   2. ~/.aws/credentials (aws configure)
 *   3. ECS task role (IAM — automatic in production)
 *
 *   For the hackathon demo, export your credentials from bedrockkeys:
 *     node -e "
 *       const d = Buffer.from(require('fs').readFileSync('bedrockkeys','utf8').trim(),'base64').toString();
 *       const [id,,secret] = d.split(/[\n:]/);
 *       console.log('export AWS_ACCESS_KEY_ID='+id.split('=')[1]);
 *       console.log('export AWS_SECRET_ACCESS_KEY='+secret.split('=')[1]);
 *     "
 *   Or set them directly in backend/.env.demo (see that file).
 *
 * FALLBACK:
 *   suggest() throws on any error — the caller in replies.ts catches it and
 *   falls back to the fixed safe reply set (FR-7.3). Zero user-visible failure.
 *   The AbortSignal is wired to the 2-second timeout budget from the route.
 */

import {
  BedrockRuntimeClient,
  InvokeModelCommand,
} from '@aws-sdk/client-bedrock-runtime';

import type { BedrockPort, SmartReplyRequest } from './bedrock.js';

// Confirmed available: amazon.nova-micro-v1:0 (us-east-1, no EULA gate)
const MODEL_ID = 'amazon.nova-micro-v1:0';
const REGION   = process.env.AWS_REGION ?? process.env.BEDROCK_REGION ?? 'us-east-1';

export class RealBedrock implements BedrockPort {
  private readonly client: BedrockRuntimeClient;

  constructor() {
    this.client = new BedrockRuntimeClient({ region: REGION });
  }

  /**
   * Return up to 3 short contextual doorbell reply suggestions.
   * The AbortSignal carries the caller's 2-second timeout budget.
   * Throws on any error so the caller falls back to the safe set (FR-7.3).
   */
  async suggest(request: SmartReplyRequest, signal: AbortSignal): Promise<string[]> {
    const prompt = buildPrompt(request);

    // Nova Micro request body — Messages API (converse-compatible schema)
    const body = JSON.stringify({
      messages: [
        {
          role: 'user',
          content: [{ type: 'text', text: prompt }],
        },
      ],
      inferenceConfig: {
        maxTokens:   120,   // 3 short replies fit in ~60 tokens; 120 is safe headroom
        temperature: 0.4,   // low temperature → consistent, on-topic replies
        topP:        0.9,
      },
    });

    const command = new InvokeModelCommand({
      modelId:     MODEL_ID,
      contentType: 'application/json',
      accept:      'application/json',
      body:        Buffer.from(body),
    });

    // Forward the caller's AbortSignal so the 2-second timeout cancels the SDK call.
    const response = await this.client.send(command, { abortSignal: signal });

    const raw     = Buffer.from(response.body).toString('utf-8');
    const parsed  = JSON.parse(raw) as NovaResponse;
    const text    = parsed?.output?.message?.content?.[0]?.text ?? '';

    const suggestions = parseReplies(text);
    if (suggestions.length === 0) {
      // Model returned something unparseable — let the fallback handle it
      throw new Error(`Nova Micro returned unparseable output: ${text.slice(0, 100)}`);
    }
    return suggestions.slice(0, 3);
  }
}

// ---------------------------------------------------------------------------
// Prompt builder
// ---------------------------------------------------------------------------

function buildPrompt({ visitorText, language }: SmartReplyRequest): string {
  // Keep the prompt minimal and token-efficient.
  // Nova Micro is fast but small — terse, direct prompts work best.
  return [
    `You are a doorbell reply assistant for a deaf person.`,
    `The visitor at the door said: "${visitorText}"`,
    `Language: ${language}`,
    ``,
    `Reply with EXACTLY 3 short spoken phrases the resident can use to respond`,
    `(each 2-6 words, natural spoken English, no dashes, no bullet symbols).`,
    `Output only the 3 phrases, one per line, nothing else.`,
  ].join('\n');
}

// ---------------------------------------------------------------------------
// Response parser — handles Nova Micro's output format
// ---------------------------------------------------------------------------

type NovaResponse = {
  output?: {
    message?: {
      content?: Array<{ type: string; text?: string }>;
    };
  };
};

function parseReplies(text: string): string[] {
  return text
    .split('\n')
    .map(l =>
      l
        .replace(/^\s*[\d]+[.)]\s*/, '')  // strip leading "1." "1)" etc.
        .replace(/^[-*•]\s*/, '')          // strip bullet characters
        .replace(/[–—]/g, '-')             // replace em/en dashes (a11y rule)
        .trim()
    )
    .filter(l => l.length > 0 && l.length <= 80);  // drop blank lines and overlong lines
}
