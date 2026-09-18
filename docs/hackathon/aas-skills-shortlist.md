# AAS Catalog — Skills Shortlist for Threshold

Searched the `agentic-awesome-skills` catalog (~2,127 skills) for what accelerates a Flutter + Ring +
AWS + accessibility build. Ranked by relevance to Threshold.

## Tier 1 — use these

| Skill | Why it maps to Threshold |
|---|---|
| **`flutter-expert`** | Dart 3, advanced widgets, multi-platform, **Riverpod** (our state choice). Directly the app layer. `category: mobile · risk: safe` |
| **`amazon-alexa`** | Despite the name, covers the **AWS voice ecosystem — Lambda, Polly, Transcribe, Lex** — i.e. exactly the Clarity Mode (Transcribe) and AWS Builder integration. |
| **`audio-transcriber`** | Speech-to-text patterns (Whisper, STT) — informs both Clarity Mode and the Privacy-Mode on-device path. |
| **`aws-serverless`** | Lambda / API Gateway / DynamoDB / SAM/CDK — the backend that handles Ring OAuth, webhooks, and fronts Transcribe/Bedrock. `risk: critical` — review its output carefully. |

## Tier 2 — pull in during the accessibility pass (days 23–30)

| Skill | Why |
|---|---|
| **`wcag-audit-patterns`** | WCAG **2.2** audit + remediation — the exact standard Ring mandates and our core differentiator. |
| **`screen-reader-testing`** | Practical screen-reader validation (TalkBack/VoiceOver). |
| **`ui-a11y` / `fixing-accessibility`** | General a11y implementation and fixes. |

## Tier 3 — situational

| Skill | When |
|---|---|
| **`voice-agents`** | Only if we expand the reply flow; be careful not to drift into "chatbot" territory (explicitly a non-goal). |
| **`aws-cost-optimizer` / `aws-cost-operations`** | Keep demo/free-tier spend in check. |
| **`aws-mcp-setup`** | If we wire an MCP surface for the AWS side. |

## Notes

- These are `SKILL.md` playbooks (reference material), not runnable code — treat them as expert guidance to
  load when working the matching layer.
- `flutter-expert` + `amazon-alexa` (for Transcribe/Polly) + `wcag-audit-patterns` are the three highest-
  leverage picks. Load them at the corresponding phase, not all at once.
- `caveman` (the other cloned repo) is a token-reduction tool for agent runs — a cost optimization for the
  build process, not a Threshold building block.
