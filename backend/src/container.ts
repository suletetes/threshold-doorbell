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
  DeviceAccountStorePort,
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
import { MemoryDeviceAccountStore } from './services/fixtures/memory-device-account-store.js';
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
  deviceAccountStore: DeviceAccountStorePort;
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
  deviceAccountStore?: DeviceAccountStorePort;
  metrics?: MetricsPort;
}

/**
 * Environments that may boot on in-memory fixtures. Any other environment is a
 * real deployment and MUST supply real adapters via overrides.
 */
const FIXTURE_ENVS = new Set(['local', 'demo', 'test']);

/**
 * The real-adapter ports that a non-fixture deployment MUST inject. Real
 * KMS/DynamoDB/Transcribe/Bedrock/FCM/Ring adapters are DEFERRED (there is no
 * AWS or Ring Partner access in this environment); they are not implemented
 * here. The guard below only enforces that a staging/prod boot cannot silently
 * fall back to fixtures and in-memory stores (CRIT-02): it fails closed with a
 * clear error until those adapters are supplied.
 */
const REQUIRED_REAL_PORTS: readonly (keyof ContainerOverrides)[] = [
  'crypto',
  'ring',
  'ringSignaling',
  'transcribe',
  'bedrock',
  'push',
  'tokenStore',
  'eventStore',
  'conversationStore',
  'deviceAccountStore',
];

/**
 * Build the container for a given config. In "local"/"demo"/"test" this is
 * entirely fixtures. Tests pass overrides to inject their own fixture instances
 * so they can drive failure modes. For any other environment (for example
 * "staging") the container FAILS CLOSED: it throws unless every real-adapter
 * port is supplied via overrides, so a real deployment can never silently run
 * on fixtures and per-process in-memory stores (CRIT-02).
 */
export function buildContainer(config: Config, overrides: ContainerOverrides = {}): Container {
  if (!FIXTURE_ENVS.has(config.env)) {
    const missing = REQUIRED_REAL_PORTS.filter((port) => overrides[port] === undefined);
    if (missing.length > 0) {
      throw new Error(
        `Refusing to boot env "${config.env}" on in-memory fixtures. ` +
          `Supply real adapters for: ${missing.join(', ')}. ` +
          'Fixtures are only permitted in local, demo and test.',
      );
    }
  }

  const crypto = overrides.crypto ?? new LocalCrypto(config.sessionSecret);
  const ring = overrides.ring ?? new FixtureRing();
  const ringSignaling = overrides.ringSignaling ?? new FixtureRingSignaling();
  const transcribe = overrides.transcribe ?? new FixtureTranscribe();
  const bedrock = overrides.bedrock ?? new FixtureBedrock();
  const push = overrides.push ?? new FixturePush();
  const tokenStore = overrides.tokenStore ?? new MemoryTokenStore();
  const eventStore = overrides.eventStore ?? new MemoryEventStore();
  const conversationStore = overrides.conversationStore ?? new MemoryConversationStore();
  const deviceAccountStore = overrides.deviceAccountStore ?? new MemoryDeviceAccountStore();
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
    deviceAccountStore,
    ringTokens: new RingTokenService(ring, tokenStore, crypto),
    ringGateway: new RingGateway(ring),
    metrics,
  };
}
