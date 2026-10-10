// Test harness: build a Fastify app wired to fixture adapters, returning both
// the app and the concrete fixtures so tests can drive failure modes.

import { loadConfig } from '../../src/config.js';
import { buildContainer, type ContainerOverrides } from '../../src/container.js';
import { buildApp } from '../../src/app.js';
import { issueSession } from '../../src/security/session.js';
import { FixtureRing } from '../../src/services/fixtures/fixture-ring.js';
import { FixtureRingSignaling } from '../../src/services/fixtures/fixture-ring-signaling.js';
import { FixtureTranscribe } from '../../src/services/fixtures/fixture-transcribe.js';
import { FixtureBedrock } from '../../src/services/fixtures/fixture-bedrock.js';
import { FixturePush } from '../../src/services/fixtures/fixture-push.js';
import { LocalCrypto } from '../../src/services/fixtures/local-crypto.js';
import { InMemoryMetricsSink } from '../../src/observability/metrics.js';
import {
  MemoryConversationStore,
  MemoryEventStore,
  MemoryTokenStore,
} from '../../src/services/fixtures/memory-stores.js';
import { MemoryDeviceAccountStore } from '../../src/services/fixtures/memory-device-account-store.js';

export async function buildTestApp() {
  const config = loadConfig({ THRESHOLD_ENV: 'local', SESSION_SECRET: 'test-secret-for-sessions' });
  const ring = new FixtureRing();
  const ringSignaling = new FixtureRingSignaling();
  const transcribe = new FixtureTranscribe();
  const bedrock = new FixtureBedrock();
  const push = new FixturePush();
  const crypto = new LocalCrypto(config.sessionSecret);
  const tokenStore = new MemoryTokenStore();
  const eventStore = new MemoryEventStore();
  const conversationStore = new MemoryConversationStore();
  const deviceAccountStore = new MemoryDeviceAccountStore();
  const metrics = new InMemoryMetricsSink();

  const overrides: ContainerOverrides = {
    ring,
    ringSignaling,
    transcribe,
    bedrock,
    push,
    crypto,
    tokenStore,
    eventStore,
    conversationStore,
    deviceAccountStore,
    metrics,
  };
  const container = buildContainer(config, overrides);
  const app = await buildApp(container);
  await app.ready();

  return {
    app,
    config,
    container,
    metrics,
    signalingService: app.signalingService,
    ring,
    ringSignaling,
    transcribe,
    bedrock,
    push,
    crypto,
    tokenStore,
    eventStore,
    conversationStore,
    deviceAccountStore,
  };
}

/** Issue a valid session token for a resident (bypasses OAuth for route tests). */
export function sessionFor(sub: string, secret: string): string {
  // Delegate to the real issuer so tests exercise the real verify path.
  return issueSession(sub, secret);
}
