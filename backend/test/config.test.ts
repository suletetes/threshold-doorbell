import { describe, it, expect } from 'vitest';
import { ConfigError, isDeployableEnv, loadConfig } from '../src/config.js';

const STRONG = 'x'.repeat(40);

// MED-32: config is validated, honours its env argument, and fails fast outside
// local on insecure defaults, unknown envs and bad ports.
describe('loadConfig validation (MED-32)', () => {
  it('honours the passed-in env argument instead of process.env', () => {
    const config = loadConfig({ THRESHOLD_ENV: 'local', SESSION_SECRET: 'passed-in-secret' });
    expect(config.sessionSecret).toBe('passed-in-secret');
  });

  it('rejects an unknown THRESHOLD_ENV', () => {
    expect(() => loadConfig({ THRESHOLD_ENV: 'prod' })).toThrow(ConfigError);
    expect(() => loadConfig({ THRESHOLD_ENV: 'prod' })).toThrow(/Unknown THRESHOLD_ENV/);
  });

  it('rejects a non-numeric PORT', () => {
    expect(() => loadConfig({ THRESHOLD_ENV: 'local', PORT: 'abc' })).toThrow(/Invalid PORT/);
  });

  it('fails fast when a default session secret is used outside local', () => {
    expect(() =>
      loadConfig({
        THRESHOLD_ENV: 'staging',
        WEBHOOK_HMAC_KEY: STRONG,
        RING_CLIENT_SECRET: STRONG,
      }),
    ).toThrow(/SESSION_SECRET is still the insecure local default/);
  });

  it('fails fast when a secret is too short outside local', () => {
    expect(() =>
      loadConfig({
        THRESHOLD_ENV: 'staging',
        SESSION_SECRET: 'short',
        WEBHOOK_HMAC_KEY: STRONG,
        RING_CLIENT_SECRET: STRONG,
      }),
    ).toThrow(/SESSION_SECRET is too short/);
  });

  it('accepts strong secrets outside local', () => {
    const config = loadConfig({
      THRESHOLD_ENV: 'staging',
      SESSION_SECRET: STRONG,
      WEBHOOK_HMAC_KEY: STRONG,
      RING_CLIENT_SECRET: STRONG,
      PORT: '9090',
    });
    expect(config.env).toBe('staging');
    expect(config.port).toBe(9090);
  });

  it('allows insecure local defaults in local', () => {
    expect(() => loadConfig({ THRESHOLD_ENV: 'local' })).not.toThrow();
  });

  // #5 invariant: the secret-strength exemption applies ONLY to the
  // non-deployable envs (local, test), never to a deployable env.
  it('exempts the test harness from the secret-strength guard (non-deployable env)', () => {
    expect(() => loadConfig({ THRESHOLD_ENV: 'test' })).not.toThrow();
    expect(isDeployableEnv('test')).toBe(false);
    expect(isDeployableEnv('local')).toBe(false);
  });

  it('treats staging and demo as deployable, so they must pass the secret guard', () => {
    expect(isDeployableEnv('staging')).toBe(true);
    expect(isDeployableEnv('demo')).toBe(true);
    // A deployable env still rejects the insecure default even though "demo"
    // may boot on fixtures (container.ts): the two concerns are separate.
    expect(() => loadConfig({ THRESHOLD_ENV: 'demo' })).toThrow(
      /SESSION_SECRET is still the insecure local default/,
    );
  });
});
