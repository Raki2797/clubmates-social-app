import { buildApp } from "./app.js";
import { env } from "./config/env.js";
import { closePool } from "./db/pool.js";

const app = await buildApp();

const shutdown = async () => {
  app.log.info("Shutting down");
  await app.close();
  await closePool();
};

process.on("SIGINT", () => {
  shutdown().finally(() => process.exit(0));
});

process.on("SIGTERM", () => {
  shutdown().finally(() => process.exit(0));
});

await app.listen({
  host: env.host,
  port: env.port
});
