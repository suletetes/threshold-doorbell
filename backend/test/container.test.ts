import { describe, it, expect } from 'vitest';
import { buildContainer, type ContainerOverrides } from '../src/container.js';
import { loadConfig, type Config } from '../src/config.js';
import { FixtureRing } from '../src/services/fixtures/fixture-ring.js';
import { FixtureRingSignaling } from '../src/services/fixtures/fixture-ring-signaling.js';
import { FixtureTranscribe } from '../src/services/fixtures/fixture-transcribe.js';
import { FixtureBedrock } from '../src/services/fixtures/fixture-bedrock.js';
import { FixturePush } from '../src/services/fixtures/fixture-push.js';
import { LocalCrypto } from '../src/services/fixtures/local-crypto.js';
import {
  MemoryConversationStore,
  MemoryEventStore,
  MemoryTokenStore,
} from '../src/services/fixtures/memory-stores.js';

// CRIT-02 regression: a real deployment must never silently boot on fixtures.
describe('buildContainer fail-closed (CRIT-02)', () => {
  function allOverrides(secret: string): ContainerOverrides {
    return {
      ring: new FixtureRing(),
      ringSignaling: new FixtureRingSignaling(),
      transcribe: new FixtureTranscribe(),
      bedrock: new FixtureBedrock(),
      push: new FixturePush(),
      crypto: new LocalCrypto(secret),
      tokenStore: new MemoryTokenStore(),
      eventStore: new MemoryEventStore(),
      conversationStore: new MemoryConversationStore(),
    };
  }

  it('succeeds for env="local" with no overrides', () => {
    const config = loadConfig({ THRESHOLD_ENV: 'local', SESSION_SECRET: 'test-secret-for-sessions' });
    expect(() => buildContainer(config)).not.toThrow();
  });

  it('throws for env="staging" with no real adapters supplied', () => {
    // Build a staging config directly; loadConfig would also accept this value
    // until MED-32 validation lands, so we assert the container guard itself.
    const config: Config = {
      ...loadConfig({ THRESHOLD_ENV: 'local', SESSION_SECRET: 'test-secret-for-sessions' }),
      env: 'staging',
    };
    expect(() => buildContainer(config)).toThrow(/Refusing to boot env "staging"/);
  });

  it('names the missing real-adapter ports in the error', () => {
    const config: Config = {
      ...loadConfig({ THRESHOLD_ENV: 'local', SESSION_SECRET: 'test-secret-for-sessions' }),
      env: 'staging',
    };
    expect(() => buildContainer(config)).toThrow(/ring, ringSignaling/);
  });

  it('succeeds for env="staging" when every real adapter is supplied', () => {
    const base = loadConfig({ THRESHOLD_ENV: 'local', SESSION_SECRET: 'test-secret-for-sessions' });
    const config: Config = { ...base, env: 'staging' };
    expect(() => buildContainer(config, allOverrides(config.sessionSecret))).not.toThrow();
  });
});
