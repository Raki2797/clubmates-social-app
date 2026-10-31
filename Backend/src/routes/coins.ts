import { FastifyInstance } from "fastify";
import { query, withTransaction } from "../db/pool.js";
import { authenticate } from "../plugins/auth.js";
import { sendError } from "../utils/http.js";

const WELCOME_BONUS = 150;

async function ensureWallet(
  userId: string
): Promise<{ id: string; balance: number; created_at: Date; wasCreated: boolean }> {
  const existing = await query<{ id: string; balance: number; created_at: Date }>(
    `SELECT id, balance, created_at FROM wallets WHERE user_id = $1`,
    [userId]
  );
  if (existing.rows[0]) {
    return { ...existing.rows[0], wasCreated: false };
  }

  const result = await withTransaction(async (client) => {
    const wallet = await client.query<{ id: string; balance: number; created_at: Date }>(
      `INSERT INTO wallets (user_id, balance, bonus_balance)
       VALUES ($1, $2, $2)
       ON CONFLICT (user_id) DO UPDATE SET user_id = EXCLUDED.user_id
       RETURNING id, balance, created_at`,
      [userId, WELCOME_BONUS]
    );
    const w = wallet.rows[0];

    await client.query(
      `INSERT INTO coin_transactions (user_id, type, amount, balance_after, metadata)
       VALUES ($1, 'welcome_bonus', $2, $2, '{"source":"welcome"}'::jsonb)`,
      [userId, WELCOME_BONUS]
    );

    return { ...w, wasCreated: true };
  });

  return result;
}

export async function coinRoutes(app: FastifyInstance): Promise<void> {
  app.get("/wallet", { preHandler: authenticate }, async (request) => {
    const wallet = await ensureWallet(request.auth.userId);
    return { balance: wallet.balance, createdAt: wallet.created_at.toISOString() };
  });

  app.get("/wallet/packages", { preHandler: authenticate }, async () => {
    const result = await query(
      `SELECT id, slug, coins, price_inr AS "priceInr", bonus_pct AS "bonusPct"
       FROM coin_packages
       WHERE is_active = true
       ORDER BY position ASC`
    );
    return { packages: result.rows };
  });

  app.post<{ Body: { slug?: string } }>(
    "/wallet/purchase",
    { preHandler: authenticate },
    async (request, reply) => {
      const slug = request.body?.slug;
      if (!slug) {
        return sendError(reply, 400, "slug is required");
      }

      const pkgResult = await query<{
        id: string; coins: number; price_inr: number;
      }>(
        `SELECT id, coins, price_inr FROM coin_packages WHERE slug = $1 AND is_active = true`,
        [slug]
      );
      if (!pkgResult.rows[0]) {
        return sendError(reply, 404, "Package not found");
      }
      const pkg = pkgResult.rows[0];

      const result = await withTransaction(async (client) => {
        const walletResult = await client.query<{ balance: number }>(
          `INSERT INTO wallets (user_id, balance, bonus_balance)
           VALUES ($1, 0, 0)
           ON CONFLICT (user_id) DO UPDATE SET user_id = EXCLUDED.user_id
           RETURNING balance`,
          [request.auth.userId]
        );
        const currentBalance = walletResult.rows[0]?.balance ?? 0;
        const newBalance = currentBalance + pkg.coins;

        await client.query(
          `UPDATE wallets SET balance = $1 WHERE user_id = $2`,
          [newBalance, request.auth.userId]
        );

        const txResult = await client.query<{ id: string }>(
          `INSERT INTO coin_transactions (user_id, type, amount, balance_after, reference_id, metadata)
           VALUES ($1, 'purchase', $2, $3, $4, $5)
           RETURNING id`,
          [
            request.auth.userId,
            pkg.coins,
            newBalance,
            pkg.id,
            JSON.stringify({ slug, priceInr: pkg.price_inr })
          ]
        );

        return { coinsAdded: pkg.coins, newBalance, transactionId: txResult.rows[0].id };
      });

      return { ok: true, ...result };
    }
  );

  app.get<{ Querystring: { limit?: string; before?: string } }>(
    "/wallet/transactions",
    { preHandler: authenticate },
    async (request) => {
      const limit = Math.min(parseInt(request.query.limit ?? "20", 10) || 20, 100);
      const before = request.query.before;

      const result = await query<{
        id: string; type: string; amount: number;
        balance_after: number; metadata: unknown; created_at: Date;
      }>(
        `SELECT id, type, amount, balance_after, metadata, created_at
         FROM coin_transactions
         WHERE user_id = $1
           AND ($2::timestamptz IS NULL OR created_at < $2::timestamptz)
         ORDER BY created_at DESC
         LIMIT $3`,
        [request.auth.userId, before ?? null, limit + 1]
      );

      const rows = result.rows;
      const hasMore = rows.length > limit;
      const transactions = rows.slice(0, limit).map((r) => ({
        id: r.id,
        type: r.type,
        amount: r.amount,
        balanceAfter: r.balance_after,
        metadata: r.metadata,
        createdAt: r.created_at.toISOString()
      }));

      return { transactions, hasMore };
    }
  );

  app.get("/wallet/treat-pricing", { preHandler: authenticate }, async () => {
    const result = await query(
      `SELECT treat_type AS "treatType", sender_cost AS "senderCost", receiver_credit AS "receiverCredit"
       FROM treat_pricing
       WHERE is_active = true
       ORDER BY sender_cost ASC`
    );
    return { pricing: result.rows };
  });
}

export { ensureWallet };
