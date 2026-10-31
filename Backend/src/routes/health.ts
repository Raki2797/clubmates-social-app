import { FastifyInstance } from "fastify";
import { query } from "../db/pool.js";

export async function healthRoutes(app: FastifyInstance): Promise<void> {
  app.get("/health", async () => {
    const result = await query<{ ok: number }>("SELECT 1 AS ok");
    return {
      ok: result.rows[0]?.ok === 1,
      service: "clubmates-backend"
    };
  });
}
