// Test harness: build a Fastify app wired to fixture adapters, returning both
// the app and the concrete fixtures so tests can drive failure modes.

import { loadConfig } from '../../src/config.js';
import { buildContainer, type ContainerOverrides } from '../../src/container.js';
import { buildApp } from '../../src/app.js';
import { issueSession } from '../../src/security/session.js';
import { FixtureRing } from '../../src/services/fixtures/fixture-ring.js';
import { FixtureBedrock } from '../../src/services/fixtures/fixture-bedrock.js';
import { FixturePush } from '../../src/services/fixtures/fixture-push.js';
import { LocalCrypto } from '../../src/services/fixtures/local-crypto.js';
import {
  MemoryConversationStore,
  MemoryEventStore,
  MemoryTokenStore,
} from '../../src/services/fixtures/memory-stores.js';

export async function buildTestApp() {
  const config = loadConfig({ THRESHOLD_ENV: 'local', SESSION_SECRET: 'test-secret-for-sessions' });
  const ring = new FixtureRing();
  const bedrock = new FixtureBedrock();
  const push = new FixturePush();
  const crypto = new LocalCrypto(config.sessionSecret);
  const tokenStore = new MemoryTokenStore();
  const eventStore = new MemoryEventStore();
  const conversationStore = new MemoryConversationStore();

  const overrides: ContainerOverrides = {
    ring,
    bedrock,
    push,
    crypto,
    tokenStore,
    eventStore,
    conversationStore,
  };
  const container = buildContainer(config, overrides);
  const app = await buildApp(container);
  await app.ready();

  return { app, config, container, ring, bedrock, push, crypto, tokenStore, eventStore, conversationStore };
}

/** Issue a valid session token for a resident (bypasses OAuth for route tests). */
export function sessionFor(sub: string, secret: string): string {
  // Delegate to the real issuer so tests exercise the real verify path.
  return issueSession(sub, secret);
}
