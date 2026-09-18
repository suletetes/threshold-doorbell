// Process entrypoint. Boots the Fastify app with a container built from config.
import { loadConfig } from './config.js';
import { buildContainer } from './container.js';
import { buildApp } from './app.js';
import { getLogger } from './observability/logger.js';

async function main(): Promise<void> {
  const config = loadConfig();
  const container = buildContainer(config);
  const app = await buildApp(container);
  const log = getLogger();
  try {
    await app.listen({ host: config.host, port: config.port });
    log.info({ env: config.env, port: config.port }, 'threshold backend listening');
  } catch (err) {
    log.error({ err }, 'failed to start');
    process.exit(1);
  }
}

void main();
