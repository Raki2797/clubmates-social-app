import cors from "@fastify/cors";
import multipart from "@fastify/multipart";
import websocket from "@fastify/websocket";
import Fastify from "fastify";
import type { FastifyRequest } from "fastify";
import { env } from "./config/env.js";
import { registerAccountDeletionPurge } from "./jobs/accountDeletion.js";
import { registerEmbeddingWorker } from "./services/embeddingWorker.js";
import { configureRealtimeLogger, registerRealtimeConnection } from "./realtime/chatHub.js";
import { authRoutes } from "./routes/auth.js";
import { discoveryRoutes } from "./routes/discovery.js";
import { healthRoutes } from "./routes/health.js";
import { coinRoutes } from "./routes/coins.js";
import { inviteRoutes } from "./routes/invites.js";
import { matchRoutes } from "./routes/matches.js";
import { safetyRoutes } from "./routes/safety.js";
import { userRoutes } from "./routes/users.js";
import { venueRoutes } from "./routes/venues.js";
import { venueVotingRoutes } from "./routes/venueVoting.js";
import { verifyAccessToken } from "./utils/auth.js";

export async function buildApp() {
  const app = Fastify({
    logger: {
      level: env.nodeEnv === "development" ? "debug" : "info",
      serializers: {
        req(request: FastifyRequest) {
          return {
            method: request.method,
            url: request.url.split("?")[0],
            host: request.host,
            remoteAddress: request.ip,
            remotePort: request.socket.remotePort
          };
        }
      }
    }
  });
  configureRealtimeLogger(app.log);

  await app.register(cors, {
    origin: env.corsOrigin.includes("*") ? true : env.corsOrigin
  });
  await app.register(multipart);
  await app.register(websocket);

  app.get("/", async () => ({
    ok: true,
    service: "clubmates-backend",
    health: "/health"
  }));

  await app.register(healthRoutes);
  await app.register(authRoutes);
  await app.register(userRoutes);
  await app.register(venueRoutes);
  await app.register(venueVotingRoutes);
  await app.register(discoveryRoutes);
  await app.register(coinRoutes, { prefix: "/v1" });
  await app.register(inviteRoutes);
  await app.register(matchRoutes);
  await app.register(safetyRoutes);

  app.get("/v1/ws", { websocket: true }, async (connection, request) => {
    const token = new URL(request.url, "http://localhost").searchParams.get("token");
    if (!token) {
      connection.close(1008, "Missing token");
      return;
    }

    try {
      const auth = verifyAccessToken(token);
      registerRealtimeConnection(auth, connection);
    } catch {
      connection.close(1008, "Invalid token");
    }
  });

  app.setErrorHandler((error, _request, reply) => {
    app.log.error(error);
    reply.code(500).send({ error: "Internal server error" });
  });

  registerAccountDeletionPurge(app);
  registerEmbeddingWorker(app);

  return app;
}
