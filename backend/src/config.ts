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
  webhookHmacKey: string; // primary key (used to sign in tests / tooling)
  webhookHmacKeys: string[]; // accepted keys, newest first, for rotation (MED-38)
  wsAllowedOrigins: string[]; // browser Origins allowed to open a WebSocket (MED-34)
  kmsKeyId: string;
  limits: {
    // MED-29: max JSON request body in bytes. Lowered from Fastify's 1 MiB
    // default; no legitimate request is this large.
    bodyLimitBytes: number;
    // MED-29: HTTP rate limit (requests per window) and the window in ms.
    rateLimitMax: number;
    rateLimitWindowMs: number;
    // HIGH-22: max audio frame bytes accepted on a WebSocket (ws maxPayload).
    wsMaxPayloadBytes: number;
    // HIGH-22: max concurrent /asr/stream sessions per resident.
    asrMaxSessionsPerResident: number;
    // HIGH-22: hard cap on a single /asr/stream session duration (ms).
    asrMaxSessionMs: number;
    // HIGH-22: how long to wait for the upstream Transcribe stream to open (ms).
    asrOpenTimeoutMs: number;
    // HIGH-22: max audio frames buffered while the stream is opening.
    asrMaxPendingFrames: number;
  };
}

/** Read a key from the SUPPLIED env map (MED-32: honour the argument). */
function readEnv(env: NodeJS.ProcessEnv, key: string, fallback: string): string {
  const v = env[key];
  return v === undefined || v === '' ? fallback : v;
}

/** Read a positive-integer limit from the env, rejecting a non-numeric value. */
function readPositiveInt(env: NodeJS.ProcessEnv, key: string, fallback: number): number {
  const raw = env[key];
  if (raw === undefined || raw === '') return fallback;
  const n = Number.parseInt(raw, 10);
  if (!Number.isInteger(n) || n <= 0) {
    throw new ConfigError(`Invalid ${key} "${raw}". Expected a positive integer.`);
  }
  return n;
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
    // MED-38: accept a comma-separated key list so a webhook signing key can be
    // rotated with an overlap window. The primary key is always first.
    webhookHmacKeys: parseKeyList(
      readEnv(env, 'WEBHOOK_HMAC_KEY', DEFAULT_WEBHOOK_HMAC_KEY),
      readEnv(env, 'WEBHOOK_HMAC_KEYS', ''),
    ),
    // MED-34: browser Origins allowed to open a WebSocket. Empty by default, so
    // only native clients (no Origin header) connect until origins are set.
    wsAllowedOrigins: readEnv(env, 'WS_ALLOWED_ORIGINS', '')
      .split(',')
      .map((o) => o.trim())
      .filter((o) => o !== ''),
    kmsKeyId: readEnv(env, 'KMS_KEY_ID', 'alias/threshold-ring-tokens'),
    limits: {
      bodyLimitBytes: readPositiveInt(env, 'BODY_LIMIT_BYTES', 64 * 1024),
      rateLimitMax: readPositiveInt(env, 'RATE_LIMIT_MAX', 300),
      rateLimitWindowMs: readPositiveInt(env, 'RATE_LIMIT_WINDOW_MS', 60 * 1000),
      wsMaxPayloadBytes: readPositiveInt(env, 'WS_MAX_PAYLOAD_BYTES', 64 * 1024),
      asrMaxSessionsPerResident: readPositiveInt(env, 'ASR_MAX_SESSIONS_PER_RESIDENT', 2),
      asrMaxSessionMs: readPositiveInt(env, 'ASR_MAX_SESSION_MS', 10 * 60 * 1000),
      asrOpenTimeoutMs: readPositiveInt(env, 'ASR_OPEN_TIMEOUT_MS', 5 * 1000),
      asrMaxPendingFrames: readPositiveInt(env, 'ASR_MAX_PENDING_FRAMES', 256),
    },
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

/** Build the accepted webhook key list: the primary key, then any extra keys. */
function parseKeyList(primary: string, extra: string): string[] {
  const extras = extra
    .split(',')
    .map((k) => k.trim())
    .filter((k) => k !== '');
  return [primary, ...extras.filter((k) => k !== primary)];
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
