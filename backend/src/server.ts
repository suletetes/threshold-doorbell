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

  // LOW-26: graceful shutdown. On SIGTERM/SIGINT close the app so open
  // WebSocket sessions and Ring URLs are torn down instead of being dropped.
  let shuttingDown = false;
  const shutdown = (signal: string): void => {
    if (shuttingDown) {
      return;
    }
    shuttingDown = true;
    log.info({ signal }, 'shutting down');
    app
      .close()
      .then(() => {
        log.info('closed cleanly');
        process.exit(0);
      })
      .catch((err: unknown) => {
        log.error({ err }, 'error during shutdown');
        process.exit(1);
      });
  };
  process.once('SIGTERM', () => shutdown('SIGTERM'));
  process.once('SIGINT', () => shutdown('SIGINT'));

  try {
    await app.listen({ host: config.host, port: config.port });
    log.info({ env: config.env, port: config.port }, 'threshold backend listening');
  } catch (err) {
    log.error({ err }, 'failed to start');
    process.exit(1);
  }
}

// LOW-26: a rejection in loadConfig/buildContainer/buildApp (outside the
// listen try) must not become an unhandled rejection.
main().catch((err: unknown) => {
  getLogger().error({ err }, 'fatal startup error');
  process.exit(1);
});
