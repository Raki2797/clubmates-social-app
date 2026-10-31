import { DbClient } from "../db/pool.js";

export type InviteAcceptanceStatus =
  | "accepted"
  | "accepted_by_like"
  | "accepted_by_invite_back";

export type PendingInvite = {
  id: string;
  sender_id: string;
  receiver_id: string;
  venue_id: string | null;
  treat_type: string;
};

export async function lockUserPair(
  client: DbClient,
  firstUserId: string,
  secondUserId: string
): Promise<void> {
  const pairKey = [firstUserId, secondUserId].sort().join(":");
  await client.query("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [pairKey]);
}

export async function expirePendingInvites(
  client: Pick<DbClient, "query">,
  firstUserId?: string,
  secondUserId?: string
): Promise<void> {
  await client.query(
    `
      UPDATE treat_invites
      SET status = 'expired', responded_at = now()
      WHERE status = 'pending'
        AND expires_at <= now()
        AND (
          $1::uuid IS NULL
          OR (
            (sender_id = $1 AND receiver_id = $2)
            OR (sender_id = $2 AND receiver_id = $1)
          )
        )
    `,
    [firstUserId ?? null, secondUserId ?? null]
  );
}

export async function findIncomingPendingInvite(
  client: DbClient,
  actorId: string,
  targetId: string
): Promise<PendingInvite | null> {
  const result = await client.query<PendingInvite>(
    `
      SELECT id, sender_id, receiver_id, venue_id, treat_type
      FROM treat_invites
      WHERE sender_id = $2
        AND receiver_id = $1
        AND status = 'pending'
        AND expires_at > now()
      ORDER BY created_at DESC
      LIMIT 1
      FOR UPDATE
    `,
    [actorId, targetId]
  );
  return result.rows[0] ?? null;
}

export async function findOutgoingPendingInvite(
  client: DbClient,
  actorId: string,
  targetId: string
): Promise<PendingInvite | null> {
  const result = await client.query<PendingInvite>(
    `
      SELECT id, sender_id, receiver_id, venue_id, treat_type
      FROM treat_invites
      WHERE sender_id = $1
        AND receiver_id = $2
        AND status = 'pending'
        AND expires_at > now()
      ORDER BY created_at DESC
      LIMIT 1
      FOR UPDATE
    `,
    [actorId, targetId]
  );
  return result.rows[0] ?? null;
}

export async function findPairMatch(
  client: DbClient,
  firstUserId: string,
  secondUserId: string
): Promise<string | null> {
  const result = await client.query<{ id: string }>(
    `
      SELECT id
      FROM matches
      WHERE (user_a_id = $1 AND user_b_id = $2)
         OR (user_a_id = $2 AND user_b_id = $1)
      ORDER BY
        (unmatched_at IS NULL AND deleted_at IS NULL) DESC,
        created_at ASC
      LIMIT 1
      FOR UPDATE
    `,
    [firstUserId, secondUserId]
  );
  return result.rows[0]?.id ?? null;
}

export async function findActivePairMatch(
  client: DbClient,
  firstUserId: string,
  secondUserId: string
): Promise<string | null> {
  const result = await client.query<{ id: string }>(
    `
      SELECT id
      FROM matches
      WHERE (
        (user_a_id = $1 AND user_b_id = $2)
        OR (user_a_id = $2 AND user_b_id = $1)
      )
        AND unmatched_at IS NULL
        AND deleted_at IS NULL
      ORDER BY created_at ASC
      LIMIT 1
      FOR UPDATE
    `,
    [firstUserId, secondUserId]
  );
  return result.rows[0]?.id ?? null;
}

export async function ensurePairMatch(
  client: DbClient,
  firstUserId: string,
  secondUserId: string,
  venueId: string | null
): Promise<string> {
  const existingMatchId = await findPairMatch(client, firstUserId, secondUserId);
  if (existingMatchId) {
    await client.query(
      `
        UPDATE matches
        SET unmatched_at = NULL,
            deleted_at = NULL,
            venue_id = COALESCE($2, venue_id),
            updated_at = now()
        WHERE id = $1
      `,
      [existingMatchId, venueId]
    );
    return existingMatchId;
  }

  const result = await client.query<{ id: string }>(
    `
      INSERT INTO matches(user_a_id, user_b_id, venue_id, deleted_at)
      VALUES (
        LEAST($1::text, $2::text)::uuid,
        GREATEST($1::text, $2::text)::uuid,
        $3,
        NULL
      )
      RETURNING id
    `,
    [firstUserId, secondUserId, venueId]
  );
  return result.rows[0].id;
}

export async function acceptInvite(
  client: DbClient,
  invite: PendingInvite,
  status: InviteAcceptanceStatus
): Promise<string> {
  const matchId = await ensurePairMatch(
    client,
    invite.sender_id,
    invite.receiver_id,
    invite.venue_id
  );

  await client.query(
    `
      UPDATE treat_invites
      SET status = CASE WHEN id = $1 THEN $3 ELSE 'accepted' END,
          match_id = $2,
          responded_at = now()
      WHERE status = 'pending'
        AND (
          (sender_id = $4 AND receiver_id = $5)
          OR (sender_id = $5 AND receiver_id = $4)
        )
    `,
    [invite.id, matchId, status, invite.sender_id, invite.receiver_id]
  );
  return matchId;
}
