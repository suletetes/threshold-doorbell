// Runtime configuration. Reads from the environment with local-fixture defaults
// so the service boots in "local" mode with no AWS and no real Ring.

export type DeploymentEnv = 'local' | 'staging' | 'demo';

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

function readEnv(key: string, fallback: string): string {
  const v = process.env[key];
  return v === undefined || v === '' ? fallback : v;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const deployment = (env.THRESHOLD_ENV ?? 'local') as DeploymentEnv;
  return {
    env: deployment,
    host: readEnv('HOST', '0.0.0.0'),
    port: Number.parseInt(readEnv('PORT', '8080'), 10),
    sessionSecret: readEnv('SESSION_SECRET', 'local-dev-session-secret-change-me'),
    ring: {
      clientId: readEnv('RING_CLIENT_ID', 'local-fixture-client'),
      clientSecret: readEnv('RING_CLIENT_SECRET', 'local-fixture-secret'),
      authorizeUrl: readEnv('RING_AUTHORIZE_URL', 'https://oauth.ring.com/oauth/authorize'),
      tokenUrl: readEnv('RING_TOKEN_URL', 'https://oauth.ring.com/oauth/token'),
      redirectUri: readEnv('RING_REDIRECT_URI', 'http://localhost:8080/oauth/callback'),
      apiBase: readEnv('RING_API_BASE', 'https://api.ring.com'),
    },
    appDeepLink: readEnv('APP_DEEP_LINK', 'threshold://auth/complete'),
    webhookHmacKey: readEnv('WEBHOOK_HMAC_KEY', 'local-fixture-hmac-key'),
    kmsKeyId: readEnv('KMS_KEY_ID', 'alias/threshold-ring-tokens'),
  };
}
