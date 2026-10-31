import { FastifyReply, FastifyRequest } from "fastify";
import { query } from "../db/pool.js";
import { AuthContext, verifyAccessToken } from "../utils/auth.js";

declare module "fastify" {
  interface FastifyRequest {
    auth: AuthContext;
  }
}

export async function authenticate(
  request: FastifyRequest,
  reply: FastifyReply
): Promise<void> {
  const header = request.headers.authorization;
  const token = header?.startsWith("Bearer ") ? header.slice("Bearer ".length) : undefined;

  if (!token) {
    await reply.code(401).send({ error: "Missing bearer token" });
    return;
  }

  try {
    const auth = verifyAccessToken(token);
    const user = await query<{
      is_active: boolean;
      deletion_scheduled_at: Date | null;
    }>(
      `
        SELECT is_active, deletion_scheduled_at
        FROM users
        WHERE id = $1
      `,
      [auth.userId]
    );

    const row = user.rows[0];
    if (!row || !row.is_active || row.deletion_scheduled_at) {
      await reply.code(401).send({ error: "Invalid or expired token" });
      return;
    }

    request.auth = auth;
  } catch {
    await reply.code(401).send({ error: "Invalid or expired token" });
  }
}
