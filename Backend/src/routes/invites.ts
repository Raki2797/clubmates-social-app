import { FastifyInstance } from "fastify";
import { query, withTransaction } from "../db/pool.js";
import { authenticate } from "../plugins/auth.js";
import { broadcastToUser } from "../realtime/chatHub.js";
import { signedProfilePhotoUrl } from "../services/profilePhotoStorage.js";
import {
  acceptInvite,
  expirePendingInvites,
  findActivePairMatch,
  findIncomingPendingInvite,
  lockUserPair
} from "../services/inviteMatchState.js";
import { asString, sendError } from "../utils/http.js";
import { serializeCompactProfile, UserRow } from "../utils/serializers.js";

type TreatType = "drink" | "dessert" | "coffee" | "starter";
type AnyClient = { query(text: string, values?: unknown[]): Promise<{ rows: Record<string, unknown>[] }> };

type InviteRow = UserRow & {
  invite_id: string;
  venue_id: string | null;
  treat_type: TreatType;
  created_at: Date;
  photo_url: string | null;
  photo_storage_key: string | null;
};

const intent = "If we both meet and vibe, I'm open to this treat.";

function isTreatType(value: unknown): value is TreatType {
  return value === "drink"
    || value === "dessert"
    || value === "coffee"
    || value === "starter";
}

async function senderProfile(userId: string) {
  const result = await query<UserRow & {
    photo_url: string | null;
    photo_storage_key: string | null;
  }>(
    `
      SELECT u.id, u.name, u.age, u.bio, u.profession, u.gender, u.height,
             u.interests, u.is_verified, u.looking_for,
             pp.cdn_url AS photo_url, pp.storage_key AS photo_storage_key
      FROM users u
      LEFT JOIN profile_photos pp ON pp.user_id = u.id AND pp.position = 0
      WHERE u.id = $1
      LIMIT 1
    `,
    [userId]
  );
  const row = result.rows[0];
  if (!row) { return null; }
  const photoUrl = row.photo_storage_key
    ? (await signedProfilePhotoUrl(row.photo_storage_key)) ?? row.photo_url
    : row.photo_url;
  return serializeCompactProfile({ ...row, photo_url: photoUrl });
}

async function getTreatPricing(
  client: AnyClient,
  treatType: TreatType
): Promise<{ senderCost: number; receiverCredit: number }> {
  const result = await client.query(
    `SELECT sender_cost, receiver_credit FROM treat_pricing WHERE treat_type = $1 AND is_active = true`,
    [treatType]
  );
  const row = result.rows[0];
  if (!row) { throw new Error(`No pricing for treat type: ${treatType}`); }
  return { senderCost: row.sender_cost as number, receiverCredit: row.receiver_credit as number };
}

export async function inviteRoutes(app: FastifyInstance): Promise<void> {
  app.get("/invites/incoming", { preHandler: authenticate }, async (request) => {
    await query(
      `
        UPDATE treat_invites
        SET status = 'expired', responded_at = now()
        WHERE receiver_id = $1
          AND status = 'pending'
          AND expires_at <= now()
      `,
      [request.auth.userId]
    );

    const result = await query<InviteRow>(
      `
        SELECT i.id AS invite_id, i.venue_id, i.treat_type, i.created_at,
               u.id, u.name, u.age, u.bio, u.profession, u.gender, u.height,
               u.interests, u.is_verified, u.looking_for,
               pp.cdn_url AS photo_url, pp.storage_key AS photo_storage_key
        FROM treat_invites i
        JOIN users u ON u.id = i.sender_id
        LEFT JOIN profile_photos pp ON pp.user_id = u.id AND pp.position = 0
        WHERE i.receiver_id = $1
          AND i.status = 'pending'
          AND i.expires_at > now()
          AND u.is_active = true
          AND u.deletion_scheduled_at IS NULL
          AND NOT EXISTS (
            SELECT 1 FROM blocks
            WHERE (blocker_id = $1 AND blocked_id = u.id)
               OR (blocker_id = u.id AND blocked_id = $1)
          )
          AND NOT EXISTS (
            SELECT 1 FROM reports
            WHERE (reporter_id = $1 AND reported_id = u.id)
               OR (reporter_id = u.id AND reported_id = $1)
          )
          AND NOT EXISTS (
            SELECT 1 FROM matches m
            WHERE (
              (m.user_a_id = $1 AND m.user_b_id = u.id)
              OR (m.user_a_id = u.id AND m.user_b_id = $1)
            )
              AND m.unmatched_at IS NULL
              AND m.deleted_at IS NULL
          )
        ORDER BY i.created_at DESC
      `,
      [request.auth.userId]
    );

    const invites = await Promise.all(result.rows.map(async (row) => {
      const photoUrl = row.photo_storage_key
        ? (await signedProfilePhotoUrl(row.photo_storage_key)) ?? row.photo_url
        : row.photo_url;
      return {
        id: row.invite_id,
        venueId: row.venue_id,
        treatType: row.treat_type,
        intent,
        createdAt: row.created_at.toISOString(),
        profile: serializeCompactProfile({ ...row, photo_url: photoUrl })
      };
    }));

    return { invites };
  });

  app.post<{
    Body: { targetUserId?: string; venueId?: string; treatType?: string };
  }>("/invites", { preHandler: authenticate }, async (request, reply) => {
    const targetUserId = asString(request.body?.targetUserId);
    const venueId = asString(request.body?.venueId);
    const treatType = request.body?.treatType;

    if (treatType === "decide_together") {
      return sendError(reply, 400, "decide_together is no longer supported");
    }

    if (!targetUserId || !venueId || !isTreatType(treatType)) {
      return sendError(reply, 400, "targetUserId, venueId, and valid treatType are required");
    }
    if (targetUserId === request.auth.userId) {
      return sendError(reply, 400, "You cannot invite yourself");
    }

    const target = await query(
      `
        SELECT 1 FROM users u
        WHERE u.id = $1
          AND u.is_active = true
          AND u.deletion_scheduled_at IS NULL
          AND u.profile_completed = true
          AND u.is_ghost_mode = false
          AND NOT EXISTS (
            SELECT 1 FROM blocks
            WHERE (blocker_id = $2 AND blocked_id = u.id)
               OR (blocker_id = u.id AND blocked_id = $2)
          )
          AND NOT EXISTS (
            SELECT 1 FROM reports
            WHERE (reporter_id = $2 AND reported_id = u.id)
               OR (reporter_id = u.id AND reported_id = $2)
          )
      `,
      [targetUserId, request.auth.userId]
    );
    if (target.rowCount === 0) {
      return sendError(reply, 404, "Target user not found");
    }

    const result = await withTransaction(async (client) => {
      await lockUserPair(client, request.auth.userId, targetUserId);
      await expirePendingInvites(client, request.auth.userId, targetUserId);

      const activeMatchId = await findActivePairMatch(client, request.auth.userId, targetUserId);
      if (activeMatchId) {
        return { isMatch: true as const, matchId: activeMatchId, invite: null };
      }

      // Get pricing and check/deduct balance atomically
      const pricing = await getTreatPricing(client, treatType);
      const cost = pricing.senderCost;

      // Ensure wallet exists (lazy create with 0 balance if no welcome bonus yet credited)
      await client.query(
        `INSERT INTO wallets (user_id, balance, bonus_balance) VALUES ($1, 0, 0) ON CONFLICT (user_id) DO NOTHING`,
        [request.auth.userId]
      );

      // Lock wallet row and check balance
      const walletResult = await client.query<{ id: string; balance: number }>(
        `SELECT id, balance FROM wallets WHERE user_id = $1 FOR UPDATE`,
        [request.auth.userId]
      );
      const wallet = walletResult.rows[0];
      if (!wallet || wallet.balance < cost) {
        const err = new Error("insufficient_coins") as Error & { statusCode: number; required: number; balance: number };
        err.statusCode = 402;
        err.required = cost;
        err.balance = wallet?.balance ?? 0;
        throw err;
      }

      const newBalance = wallet.balance - cost;
      await client.query(
        `UPDATE wallets SET balance = $1 WHERE user_id = $2`,
        [newBalance, request.auth.userId]
      );

      const txResult = await client.query<{ id: string }>(
        `INSERT INTO coin_transactions (user_id, type, amount, balance_after, metadata)
         VALUES ($1, 'invite_sent', $2, $3, $4)
         RETURNING id`,
        [request.auth.userId, -cost, newBalance, JSON.stringify({ treatType })]
      );
      const coinTxId = txResult.rows[0].id;

      const incomingInvite = await findIncomingPendingInvite(
        client,
        request.auth.userId,
        targetUserId
      );
      if (incomingInvite) {
        const matchId = await acceptInvite(client, incomingInvite, "accepted_by_invite_back");
        // Credit the new sender as receiver of the incoming invite
        await creditReceiverCoins(client, request.auth.userId, incomingInvite.treat_type as TreatType);
        return {
          isMatch: true as const,
          matchId,
          invite: incomingInvite,
          coinTxId
        };
      }

      const existingOutgoing = await client.query<{ id: string; created_at: Date }>(
        `
          SELECT id, created_at
          FROM treat_invites
          WHERE sender_id = $1
            AND receiver_id = $2
            AND status = 'pending'
            AND expires_at > now()
          ORDER BY created_at DESC
          LIMIT 1
          FOR UPDATE
        `,
        [request.auth.userId, targetUserId]
      );

      if (existingOutgoing.rows[0]) {
        // Refund the old invite's coin cost before replacing
        await refundInviteCoin(client, existingOutgoing.rows[0].id, request.auth.userId);

        await client.query(
          `
            UPDATE treat_invites
            SET status = 'expired', responded_at = now()
            WHERE sender_id = $1
              AND receiver_id = $2
              AND status = 'pending'
              AND id != $3
          `,
          [request.auth.userId, targetUserId, existingOutgoing.rows[0].id]
        );
      }

      const pending = existingOutgoing.rows[0]
        ? await client.query<{ id: string; created_at: Date }>(
          `
            UPDATE treat_invites
            SET venue_id = $2,
                treat_type = $3,
                coin_tx_id = $4,
                created_at = now(),
                expires_at = now() + INTERVAL '24 hours'
            WHERE id = $1
            RETURNING id, created_at
          `,
          [existingOutgoing.rows[0].id, venueId, treatType, coinTxId]
        )
        : await client.query<{ id: string; created_at: Date }>(
          `
            INSERT INTO treat_invites(sender_id, receiver_id, venue_id, treat_type, coin_tx_id)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING id, created_at
          `,
          [request.auth.userId, targetUserId, venueId, treatType, coinTxId]
        );

      return {
        isMatch: false as const,
        matchId: null,
        coinTxId,
        invite: {
          id: pending.rows[0].id,
          sender_id: request.auth.userId,
          receiver_id: targetUserId,
          venue_id: venueId,
          created_at: pending.rows[0].created_at
        }
      };
    }).catch((err: unknown) => {
      if (err instanceof Error && err.message === "insufficient_coins") {
        const e = err as Error & { required: number; balance: number };
        const insufficientError = { insufficientCoins: true as const, required: e.required, balance: e.balance };
        return insufficientError;
      }
      throw err;
    });

    if ("insufficientCoins" in result) {
      reply.code(402);
      return { error: "insufficient_coins", required: result.required, balance: result.balance };
    }

    const txResult = result as {
      isMatch: boolean;
      matchId: string | null;
      invite: { id: string; sender_id: string; receiver_id: string; venue_id: string | null; created_at: Date; treat_type?: string } | null;
    };

    if (txResult.isMatch) {
      if (txResult.invite) {
        const acceptedEvent = {
          type: "invite.accepted",
          inviteId: txResult.invite.id,
          matchId: txResult.matchId,
          status: "accepted_by_invite_back",
          venueId,
          createdAt: new Date().toISOString()
        };
        const [senderProfilePayload, receiverProfilePayload] = await Promise.all([
          senderProfile(request.auth.userId),
          senderProfile(targetUserId)
        ]);
        broadcastToUser(request.auth.userId, {
          ...acceptedEvent,
          profile: receiverProfilePayload
        });
        broadcastToUser(targetUserId, {
          ...acceptedEvent,
          profile: senderProfilePayload
        });
      }
      return { isMatch: true, matchId: txResult.matchId };
    }

    const profile = await senderProfile(request.auth.userId);
    if (profile && txResult.invite) {
      broadcastToUser(targetUserId, {
        type: "invite.received",
        inviteId: txResult.invite.id,
        venueId,
        treatType,
        intent,
        createdAt: txResult.invite.created_at.toISOString(),
        profile
      });
    }

    return {
      isMatch: false,
      matchId: null,
      invite: {
        id: txResult.invite!.id,
        venueId,
        treatType,
        intent,
        createdAt: txResult.invite!.created_at.toISOString()
      }
    };
  });

  app.post<{ Params: { id: string } }>(
    "/invites/:id/accept",
    { preHandler: authenticate },
    async (request, reply) => {
      const accepted = await withTransaction(async (client) => {
        const pairResult = await client.query<{
          sender_id: string;
          receiver_id: string;
        }>(
          `
            SELECT sender_id, receiver_id
            FROM treat_invites
            WHERE id = $1 AND receiver_id = $2
          `,
          [request.params.id, request.auth.userId]
        );
        const pair = pairResult.rows[0];
        if (!pair) { return null; }

        await lockUserPair(client, pair.sender_id, pair.receiver_id);
        await expirePendingInvites(client, pair.sender_id, pair.receiver_id);

        const inviteResult = await client.query<{
          id: string;
          sender_id: string;
          receiver_id: string;
          venue_id: string | null;
          treat_type: TreatType;
        }>(
          `
            SELECT id, sender_id, receiver_id, venue_id, treat_type
            FROM treat_invites
            WHERE id = $1
              AND receiver_id = $2
              AND status = 'pending'
              AND expires_at > now()
            FOR UPDATE
          `,
          [request.params.id, request.auth.userId]
        );
        const invite = inviteResult.rows[0];
        if (!invite) { return null; }

        const matchId = await acceptInvite(client, invite, "accepted");

        // Credit receiver
        await creditReceiverCoins(client, request.auth.userId, invite.treat_type);

        return {
          matchId,
          senderId: invite.sender_id,
          receiverId: invite.receiver_id,
          venueId: invite.venue_id
        };
      });

      if (!accepted) {
        return sendError(reply, 404, "Pending invite not found");
      }
      const [senderProfilePayload, receiverProfilePayload] = await Promise.all([
        senderProfile(accepted.senderId),
        senderProfile(accepted.receiverId)
      ]);
      broadcastToUser(accepted.senderId, {
        type: "invite.accepted",
        inviteId: request.params.id,
        matchId: accepted.matchId,
        status: "accepted",
        venueId: accepted.venueId,
        createdAt: new Date().toISOString(),
        profile: receiverProfilePayload
      });
      broadcastToUser(accepted.receiverId, {
        type: "invite.accepted",
        inviteId: request.params.id,
        matchId: accepted.matchId,
        status: "accepted",
        venueId: accepted.venueId,
        createdAt: new Date().toISOString(),
        profile: senderProfilePayload
      });
      return { matchId: accepted.matchId };
    }
  );

  app.post<{ Params: { id: string } }>(
    "/invites/:id/decline",
    { preHandler: authenticate },
    async (request, reply) => {
      await query(
        `
          UPDATE treat_invites
          SET status = 'expired', responded_at = now()
          WHERE id = $1
            AND receiver_id = $2
            AND status = 'pending'
            AND expires_at <= now()
        `,
        [request.params.id, request.auth.userId]
      );

      const result = await withTransaction(async (client) => {
        const inviteResult = await client.query<{ id: string; sender_id: string; treat_type: TreatType }>(
          `
            UPDATE treat_invites
            SET status = 'declined', responded_at = now()
            WHERE id = $1
              AND receiver_id = $2
              AND status = 'pending'
              AND expires_at > now()
            RETURNING id, sender_id, treat_type
          `,
          [request.params.id, request.auth.userId]
        );
        const invite = inviteResult.rows[0];
        if (!invite) { return null; }

        await refundInviteCoin(client, invite.id, invite.sender_id);
        return invite;
      });

      if (!result) {
        return sendError(reply, 404, "Pending invite not found");
      }
      return { ok: true };
    }
  );
}

async function creditReceiverCoins(
  client: AnyClient,
  receiverId: string,
  treatType: TreatType
): Promise<void> {
  const pricingResult = await client.query(
    `SELECT sender_cost, receiver_credit FROM treat_pricing WHERE treat_type = $1 AND is_active = true`,
    [treatType]
  );
  const pricingRow = pricingResult.rows[0];
  if (!pricingRow) { return; }
  const credit = pricingRow.receiver_credit as number;

  await client.query(
    `INSERT INTO wallets (user_id, balance, bonus_balance) VALUES ($1, 0, 0) ON CONFLICT (user_id) DO NOTHING`,
    [receiverId]
  );

  const walletResult = await client.query(
    `UPDATE wallets SET balance = balance + $1 WHERE user_id = $2 RETURNING balance`,
    [credit, receiverId]
  );
  const newBalance = (walletResult.rows[0]?.balance as number | undefined) ?? credit;

  await client.query(
    `INSERT INTO coin_transactions (user_id, type, amount, balance_after, metadata)
     VALUES ($1, 'invite_received', $2, $3, $4)`,
    [receiverId, credit, newBalance, JSON.stringify({ treatType })]
  );
}

async function refundInviteCoin(
  client: AnyClient,
  inviteId: string,
  senderId: string
): Promise<void> {
  const txResult = await client.query(
    `SELECT ct.id, ct.amount
     FROM treat_invites ti
     JOIN coin_transactions ct ON ct.id = ti.coin_tx_id
     WHERE ti.id = $1`,
    [inviteId]
  );
  const tx = txResult.rows[0];
  if (!tx) { return; }

  const refundAmount = Math.abs(tx.amount as number);

  const walletResult = await client.query(
    `UPDATE wallets SET balance = balance + $1 WHERE user_id = $2 RETURNING balance`,
    [refundAmount, senderId]
  );
  const newBalance = (walletResult.rows[0]?.balance as number | undefined) ?? refundAmount;

  await client.query(
    `INSERT INTO coin_transactions (user_id, type, amount, balance_after, reference_id)
     VALUES ($1, 'invite_refund', $2, $3, $4)`,
    [senderId, refundAmount, newBalance, tx.id]
  );
}
