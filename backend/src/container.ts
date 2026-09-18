// Dependency container. Wires ports to either fixtures (local/demo) or real
// adapters (staging). Routes and services receive this container so nothing
// constructs an SDK directly (ports and adapters, structure.md).

import type { Config } from './config.js';
import type { MetricsPort } from './observability/metrics.js';
import { InMemoryMetricsSink } from './observability/metrics.js';
import type { CryptoPort } from './services/crypto.js';
import type { RingPort } from './services/ring.js';
import type { RingSignalingPort } from './services/ring-signaling.js';
import type { TranscribePort } from './services/transcribe.js';
import type { BedrockPort } from './services/bedrock.js';
import type { PushPort } from './services/push.js';
import type {
  ConversationStorePort,
  EventStorePort,
  TokenStorePort,
} from './services/stores.js';
import { LocalCrypto } from './services/fixtures/local-crypto.js';
import { FixtureRing } from './services/fixtures/fixture-ring.js';
import { FixtureRingSignaling } from './services/fixtures/fixture-ring-signaling.js';
import { FixtureTranscribe } from './services/fixtures/fixture-transcribe.js';
import { FixtureBedrock } from './services/fixtures/fixture-bedrock.js';
import { FixturePush } from './services/fixtures/fixture-push.js';
import {
  MemoryConversationStore,
  MemoryEventStore,
  MemoryTokenStore,
} from './services/fixtures/memory-stores.js';
import { RingTokenService } from './services/ring-token-service.js';
import { RingGateway } from './services/ring-gateway.js';

export interface Container {
  config: Config;
  crypto: CryptoPort;
  ring: RingPort;
  ringSignaling: RingSignalingPort;
  transcribe: TranscribePort;
  bedrock: BedrockPort;
  push: PushPort;
  tokenStore: TokenStorePort;
  eventStore: EventStorePort;
  conversationStore: ConversationStorePort;
  ringTokens: RingTokenService;
  ringGateway: RingGateway;
  metrics: MetricsPort;
}

export interface ContainerOverrides {
  crypto?: CryptoPort;
  ring?: RingPort;
  ringSignaling?: RingSignalingPort;
  transcribe?: TranscribePort;
  bedrock?: BedrockPort;
  push?: PushPort;
  tokenStore?: TokenStorePort;
  eventStore?: EventStorePort;
  conversationStore?: ConversationStorePort;
  metrics?: MetricsPort;
}

/**
 * Build the container for a given config. In "local"/"demo" this is entirely
 * fixtures. Tests pass overrides to inject their own fixture instances so they
 * can drive failure modes. A "staging" build would swap in real adapters here.
 */
export function buildContainer(config: Config, overrides: ContainerOverrides = {}): Container {
  const crypto = overrides.crypto ?? new LocalCrypto(config.sessionSecret);
  const ring = overrides.ring ?? new FixtureRing();
  const ringSignaling = overrides.ringSignaling ?? new FixtureRingSignaling();
  const transcribe = overrides.transcribe ?? new FixtureTranscribe();
  const bedrock = overrides.bedrock ?? new FixtureBedrock();
  const push = overrides.push ?? new FixturePush();
  const tokenStore = overrides.tokenStore ?? new MemoryTokenStore();
  const eventStore = overrides.eventStore ?? new MemoryEventStore();
  const conversationStore = overrides.conversationStore ?? new MemoryConversationStore();
  const metrics = overrides.metrics ?? new InMemoryMetricsSink();

  return {
    config,
    crypto,
    ring,
    ringSignaling,
    transcribe,
    bedrock,
    push,
    tokenStore,
    eventStore,
    conversationStore,
    ringTokens: new RingTokenService(ring, tokenStore, crypto),
    ringGateway: new RingGateway(ring),
    metrics,
  };
}
