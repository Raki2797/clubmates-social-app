import { FastifyInstance } from "fastify";
import { query } from "../db/pool.js";
import { authenticate } from "../plugins/auth.js";
import { broadcastToUser } from "../realtime/chatHub.js";
import {
  signedProfilePhotoUrl,
  withSignedPhotoUrls
} from "../services/profilePhotoStorage.js";
import { asString, sendError } from "../utils/http.js";
import { PhotoRow, PromptRow, serializeProfile, UserRow } from "../utils/serializers.js";

type MatchRow = UserRow & {
  match_id: string;
  venue_id: string | null;
  venue_name: string | null;
  matched_at: Date;
  updated_at: Date;
  deleted_at: Date | null;
  last_message: string | null;
  last_message_at: Date | null;
  unread_count: string;
};

type MessageRow = {
  id: string;
  match_id: string;
  sender_id: string;
  body: string;
  is_read: boolean;
  created_at: Date;
  updated_at: Date;
  deleted_at: Date | null;
};

type MatchParticipantsRow = {
  user_a_id: string;
  user_b_id: string;
};

async function userCanAccessMatch(userId: string, matchId: string): Promise<boolean> {
  const result = await query(
    `
      SELECT 1
      FROM matches m
      WHERE m.id = $1
        AND m.unmatched_at IS NULL
        AND (m.user_a_id = $2 OR m.user_b_id = $2)
        AND NOT EXISTS (
          SELECT 1
          FROM blocks b
          WHERE (
            b.blocker_id = $2
            AND b.blocked_id = CASE WHEN m.user_a_id = $2 THEN m.user_b_id ELSE m.user_a_id END
          )
          OR (
            b.blocked_id = $2
            AND b.blocker_id = CASE WHEN m.user_a_id = $2 THEN m.user_b_id ELSE m.user_a_id END
          )
        )
        AND NOT EXISTS (
          SELECT 1
          FROM reports r
          WHERE (
            r.reporter_id = $2
            AND r.reported_id = CASE WHEN m.user_a_id = $2 THEN m.user_b_id ELSE m.user_a_id END
          )
          OR (
            r.reported_id = $2
            AND r.reporter_id = CASE WHEN m.user_a_id = $2 THEN m.user_b_id ELSE m.user_a_id END
          )
        )
    `,
    [matchId, userId]
  );
  return (result.rowCount ?? 0) > 0;
}

async function getMatchParticipants(matchId: string): Promise<string[]> {
  const result = await query<MatchParticipantsRow>(
    `
      SELECT user_a_id, user_b_id
      FROM matches
      WHERE id = $1
        AND unmatched_at IS NULL
    `,
    [matchId]
  );

  const row = result.rows[0];
  return row ? [row.user_a_id, row.user_b_id] : [];
}

function serializeMessage(row: MessageRow, myUserId: string) {
  return {
    id: row.id,
    matchId: row.match_id,
    body: row.body,
    isFromMe: row.sender_id === myUserId,
    senderId: row.sender_id,
    isRead: row.is_read,
    createdAt: row.created_at.toISOString(),
    deletedAt: row.deleted_at?.toISOString() ?? null
  };
}

function parseCursor(value: string | undefined): Date | null {
  if (!value) { return null; }
  const numeric = Number(value);
  const date = Number.isFinite(numeric) ? new Date(numeric) : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function parsePositiveInt(value: string | undefined, fallback: number, max: number): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 1) { return fallback; }
  return Math.min(Math.floor(parsed), max);
}

export async function matchRoutes(app: FastifyInstance): Promise<void> {
  app.get<{
    Querystring: { updatedSince?: string; limit?: string; page?: string };
  }>("/matches", { preHandler: authenticate }, async (request) => {
    const updatedSince = parseCursor(request.query.updatedSince);
    const hasDeltaCursor = Boolean(request.query.updatedSince);
    const limit = request.query.limit ? parsePositiveInt(request.query.limit, 50, 100) : null;
    const page = parsePositiveInt(request.query.page, 1, Number.MAX_SAFE_INTEGER);
    const offset = limit ? (page - 1) * limit : 0;

    const result = await query<MatchRow>(
      `
        SELECT m.id AS match_id, m.venue_id, v.name AS venue_name, m.created_at AS matched_at,
               m.updated_at, m.deleted_at,
               u.id, u.name, u.age, u.bio, u.profession, u.gender, u.height,
               u.interests, u.is_verified, u.looking_for,
               lm.body AS last_message,
               lm.created_at AS last_message_at,
               count(unread.id)::text AS unread_count
        FROM matches m
        JOIN users u ON u.id = CASE
          WHEN m.user_a_id = $1 THEN m.user_b_id
          ELSE m.user_a_id
        END
        LEFT JOIN venues v ON v.id = m.venue_id
        LEFT JOIN LATERAL (
          SELECT body, created_at
          FROM messages
          WHERE match_id = m.id
          ORDER BY created_at DESC
          LIMIT 1
        ) lm ON true
        LEFT JOIN messages unread ON unread.match_id = m.id
          AND unread.sender_id != $1
          AND unread.is_read = false
        WHERE (m.user_a_id = $1 OR m.user_b_id = $1)
          AND ($2::timestamptz IS NULL OR m.updated_at > $2)
          AND ($3::boolean = true OR (m.unmatched_at IS NULL AND m.deleted_at IS NULL))
          AND u.is_active = true
          AND u.deletion_scheduled_at IS NULL
          AND NOT EXISTS (
            SELECT 1
            FROM blocks b
            WHERE (b.blocker_id = $1 AND b.blocked_id = u.id)
               OR (b.blocked_id = $1 AND b.blocker_id = u.id)
          )
          AND NOT EXISTS (
            SELECT 1
            FROM reports r
            WHERE (r.reporter_id = $1 AND r.reported_id = u.id)
               OR (r.reported_id = $1 AND r.reporter_id = u.id)
          )
        GROUP BY m.id, v.name, u.id, lm.body, lm.created_at
        ORDER BY COALESCE(lm.created_at, m.created_at) DESC
        LIMIT COALESCE($4::integer, 2147483647)
        OFFSET $5::integer
      `,
      [request.auth.userId, updatedSince, hasDeltaCursor, limit, offset]
    );

    const total = await query<{ count: string }>(
      `
        SELECT count(*)::text AS count
        FROM matches m
        JOIN users u ON u.id = CASE
          WHEN m.user_a_id = $1 THEN m.user_b_id
          ELSE m.user_a_id
        END
        WHERE (m.user_a_id = $1 OR m.user_b_id = $1)
          AND ($2::timestamptz IS NULL OR m.updated_at > $2)
          AND ($3::boolean = true OR (m.unmatched_at IS NULL AND m.deleted_at IS NULL))
          AND u.is_active = true
          AND u.deletion_scheduled_at IS NULL
          AND NOT EXISTS (
            SELECT 1
            FROM blocks b
            WHERE (b.blocker_id = $1 AND b.blocked_id = u.id)
               OR (b.blocked_id = $1 AND b.blocker_id = u.id)
          )
          AND NOT EXISTS (
            SELECT 1
            FROM reports r
            WHERE (r.reporter_id = $1 AND r.reported_id = u.id)
               OR (r.reported_id = $1 AND r.reporter_id = u.id)
          )
      `,
      [request.auth.userId, updatedSince, hasDeltaCursor]
    );

    const matches = await Promise.all(result.rows.map(async (row) => {
      const [promptsResult, photosResult] = await Promise.all([
        query<PromptRow>(
          "SELECT id, question, answer, position FROM profile_prompts WHERE user_id = $1 ORDER BY position",
          [row.id]
        ),
        query<PhotoRow>(
          "SELECT id, storage_key, cdn_url, position FROM profile_photos WHERE user_id = $1 ORDER BY position",
          [row.id]
        )
      ]);

      return {
        id: row.match_id,
        venueId: row.venue_id,
        venueName: row.venue_name,
        profile: serializeProfile(row, promptsResult.rows, await withSignedPhotoUrls(photosResult.rows)),
        lastMessage: row.last_message ?? "It's a match!",
        lastMessageAt: (row.last_message_at ?? row.matched_at).toISOString(),
        unreadCount: Number(row.unread_count),
        isNew: row.last_message === null,
        updatedAt: row.updated_at.toISOString(),
        deletedAt: row.deleted_at?.toISOString() ?? null
      };
    }));

    return {
      matches,
      total: Number(total.rows[0]?.count ?? result.rows.length),
      page,
      limit: limit ?? result.rows.length
    };
  });

  app.get<{
    Params: { id: string };
    Querystring: { since?: string; before?: string; limit?: string; page?: string };
  }>("/matches/:id/messages", { preHandler: authenticate }, async (request, reply) => {
    if (!(await userCanAccessMatch(request.auth.userId, request.params.id))) {
      return sendError(reply, 404, "Match not found");
    }

    const limit = parsePositiveInt(request.query.limit, 50, 100);
    const page = parsePositiveInt(request.query.page, 1, Number.MAX_SAFE_INTEGER);
    const offset = (page - 1) * limit;
    const since = parseCursor(request.query.since);
    const before = parseCursor(request.query.before);
    const result = await query<MessageRow>(
      `
        WITH selected_messages AS (
          SELECT id, match_id, sender_id, body, is_read, created_at, updated_at, deleted_at
          FROM messages
          WHERE match_id = $1
            AND ($2::timestamptz IS NULL OR created_at > $2)
            AND ($3::timestamptz IS NULL OR created_at < $3)
            AND deleted_at IS NULL
          ORDER BY created_at DESC
          LIMIT $4
          OFFSET $5
        )
        SELECT id, match_id, sender_id, body, is_read, created_at, updated_at, deleted_at
        FROM selected_messages
        ORDER BY created_at ASC
      `,
      [request.params.id, since, before, limit, offset]
    );

    const total = await query<{ count: string }>(
      `
        SELECT count(*)::text AS count
        FROM messages
        WHERE match_id = $1
          AND ($2::timestamptz IS NULL OR created_at > $2)
          AND ($3::timestamptz IS NULL OR created_at < $3)
          AND deleted_at IS NULL
      `,
      [request.params.id, since, before]
    );

    return {
      messages: result.rows.map((row) => serializeMessage(row, request.auth.userId)),
      total: Number(total.rows[0]?.count ?? result.rows.length),
      page,
      limit
    };
  });

  app.post<{
    Params: { id: string };
    Body: { body?: string };
  }>("/matches/:id/messages", { preHandler: authenticate }, async (request, reply) => {
    if (!(await userCanAccessMatch(request.auth.userId, request.params.id))) {
      return sendError(reply, 404, "Match not found");
    }

    const body = asString(request.body?.body)?.trim();
    if (!body) {
      return sendError(reply, 400, "body is required");
    }

    const result = await query<MessageRow>(
      `
        INSERT INTO messages(match_id, sender_id, body, is_read)
        VALUES ($1, $2, $3, false)
        RETURNING id, match_id, sender_id, body, is_read, created_at, updated_at, deleted_at
      `,
      [request.params.id, request.auth.userId, body]
    );

    const message = result.rows[0];
    const participants = await getMatchParticipants(request.params.id);
    for (const recipientId of participants.filter((id) => id !== request.auth.userId)) {
      broadcastToUser(recipientId, {
        type: "message.created",
        message: serializeMessage(message, recipientId)
      });
    }

    return { message: serializeMessage(message, request.auth.userId) };
  });

  app.put<{
    Params: { id: string };
    Body: { upToMessageId?: string };
  }>("/matches/:id/messages/read", { preHandler: authenticate }, async (request, reply) => {
    if (!(await userCanAccessMatch(request.auth.userId, request.params.id))) {
      return sendError(reply, 404, "Match not found");
    }

    const upToMessageId = asString(request.body?.upToMessageId);
    if (upToMessageId) {
      await query(
        `
          UPDATE messages
          SET is_read = true
          WHERE match_id = $1
            AND sender_id != $2
            AND created_at <= (
              SELECT created_at FROM messages WHERE id = $3 AND match_id = $1
            )
        `,
        [request.params.id, request.auth.userId, upToMessageId]
      );
    } else {
      await query(
        "UPDATE messages SET is_read = true WHERE match_id = $1 AND sender_id != $2",
        [request.params.id, request.auth.userId]
      );
    }

    const participants = await getMatchParticipants(request.params.id);
    for (const recipientId of participants.filter((id) => id !== request.auth.userId)) {
      broadcastToUser(recipientId, {
        type: "messages.read",
        matchId: request.params.id,
        readerId: request.auth.userId,
        upToMessageId: upToMessageId ?? null
      });
    }

    return { ok: true };
  });

  app.delete<{ Params: { id: string } }>(
    "/matches/:id",
    { preHandler: authenticate },
    async (request, reply) => {
      const participants = await getMatchParticipants(request.params.id);
      const result = await query(
        `
          UPDATE matches
          SET unmatched_at = COALESCE(unmatched_at, now()),
              deleted_at = COALESCE(deleted_at, now())
          WHERE id = $1
            AND (user_a_id = $2 OR user_b_id = $2)
        `,
        [request.params.id, request.auth.userId]
      );
      if (result.rowCount === 0) {
        return sendError(reply, 404, "Match not found");
      }

      for (const recipientId of participants) {
        broadcastToUser(recipientId, {
          type: "match.unmatched",
          matchId: request.params.id
        });
      }
      return { ok: true };
    }
  );
}
