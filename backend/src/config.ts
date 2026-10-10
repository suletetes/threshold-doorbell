// Runtime configuration. Reads from the environment with local-fixture defaults
// so the service boots in "local" mode with no AWS and no real Ring. Outside
// "local" the config is validated and FAILS FAST (MED-32): an unknown
// environment, a non-numeric port, or an insecure default/short secret is a
// hard error so a deployed instance can never boot with public secrets.

export type DeploymentEnv = 'local' | 'staging' | 'demo' | 'test';

export const DEPLOYMENT_ENVS: readonly DeploymentEnv[] = ['local', 'staging', 'demo', 'test'];

// Insecure defaults used ONLY in local/demo/test. If any of these is still in
// use outside "local", loadConfig throws (MED-32).
const DEFAULT_SESSION_SECRET = 'local-dev-session-secret-change-me';
const DEFAULT_RING_CLIENT_SECRET = 'local-fixture-secret';
const DEFAULT_WEBHOOK_HMAC_KEY = 'local-fixture-hmac-key';

// Minimum length for a secret to be considered non-trivial outside local.
const MIN_SECRET_LENGTH = 32;

export interface Config {
  env: DeploymentEnv;
  host: string;
  port: number;
  sessionSecret: string;
  ring: {
    clientId: string;
    clientSecret: string;
    authorizeUrl: string;
    tokenUrl: string;
    redirectUri: string;
    apiBase: string;
  };
  appDeepLink: string;
  webhookHmacKey: string;
  kmsKeyId: string;
}

/** Read a key from the SUPPLIED env map (MED-32: honour the argument). */
function readEnv(env: NodeJS.ProcessEnv, key: string, fallback: string): string {
  const v = env[key];
  return v === undefined || v === '' ? fallback : v;
}

export class ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ConfigError';
  }
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const rawEnv = env.THRESHOLD_ENV ?? 'local';
  // MED-32: reject an unknown environment rather than silently treating it as a
  // valid DeploymentEnv (previously `THRESHOLD_ENV=prod` was accepted).
  if (!DEPLOYMENT_ENVS.includes(rawEnv as DeploymentEnv)) {
    throw new ConfigError(
      `Unknown THRESHOLD_ENV "${rawEnv}". Expected one of: ${DEPLOYMENT_ENVS.join(', ')}.`,
    );
  }
  const deployment = rawEnv as DeploymentEnv;

  // MED-32: the port must be a valid number.
  const portRaw = readEnv(env, 'PORT', '8080');
  const port = Number.parseInt(portRaw, 10);
  if (!Number.isInteger(port) || port <= 0 || port > 65535) {
    throw new ConfigError(`Invalid PORT "${portRaw}". Expected an integer in 1 to 65535.`);
  }

  const config: Config = {
    env: deployment,
    host: readEnv(env, 'HOST', '0.0.0.0'),
    port,
    sessionSecret: readEnv(env, 'SESSION_SECRET', DEFAULT_SESSION_SECRET),
    ring: {
      clientId: readEnv(env, 'RING_CLIENT_ID', 'local-fixture-client'),
      clientSecret: readEnv(env, 'RING_CLIENT_SECRET', DEFAULT_RING_CLIENT_SECRET),
      authorizeUrl: readEnv(env, 'RING_AUTHORIZE_URL', 'https://oauth.ring.com/oauth/authorize'),
      tokenUrl: readEnv(env, 'RING_TOKEN_URL', 'https://oauth.ring.com/oauth/token'),
      redirectUri: readEnv(env, 'RING_REDIRECT_URI', 'http://localhost:8080/oauth/callback'),
      apiBase: readEnv(env, 'RING_API_BASE', 'https://api.ring.com'),
    },
    appDeepLink: readEnv(env, 'APP_DEEP_LINK', 'threshold://auth/complete'),
    webhookHmacKey: readEnv(env, 'WEBHOOK_HMAC_KEY', DEFAULT_WEBHOOK_HMAC_KEY),
    kmsKeyId: readEnv(env, 'KMS_KEY_ID', 'alias/threshold-ring-tokens'),
  };

  // MED-32: outside "local" a public default or short secret is a hard error so
  // a deployed instance can never forge sessions/webhooks with known keys.
  if (deployment !== 'local' && deployment !== 'test') {
    assertStrongSecret('SESSION_SECRET', config.sessionSecret, DEFAULT_SESSION_SECRET, deployment);
    assertStrongSecret('WEBHOOK_HMAC_KEY', config.webhookHmacKey, DEFAULT_WEBHOOK_HMAC_KEY, deployment);
    assertStrongSecret(
      'RING_CLIENT_SECRET',
      config.ring.clientSecret,
      DEFAULT_RING_CLIENT_SECRET,
      deployment,
    );
  }

  return config;
}

function assertStrongSecret(
  name: string,
  value: string,
  insecureDefault: string,
  deployment: DeploymentEnv,
): void {
  if (value === insecureDefault) {
    throw new ConfigError(
      `${name} is still the insecure local default in env "${deployment}". Set a strong secret.`,
    );
  }
  if (value.length < MIN_SECRET_LENGTH) {
    throw new ConfigError(
      `${name} is too short in env "${deployment}". Use at least ${MIN_SECRET_LENGTH} characters.`,
    );
  }
}
