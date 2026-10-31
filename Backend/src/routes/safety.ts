import { FastifyInstance } from "fastify";
import { query, withTransaction } from "../db/pool.js";
import { authenticate } from "../plugins/auth.js";
import { broadcastToUser } from "../realtime/chatHub.js";
import { asString, sendError } from "../utils/http.js";

type SOSSource = "app" | "venue" | "chat" | "profile";

type SOSEventRow = {
  id: string;
  user_id: string;
  venue_id: string | null;
  match_id: string | null;
  latitude: number | null;
  longitude: number | null;
  accuracy_meters: number | null;
  source: SOSSource;
  message: string | null;
  status: string;
  created_at: Date;
};

type HiddenUserRow = {
  user_id: string;
};

type MatchIdRow = {
  id: string;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const sosSources = new Set<SOSSource>(["app", "venue", "chat", "profile"]);

function asUuid(value: unknown): string | undefined {
  const raw = asString(value);
  return raw && uuidPattern.test(raw) ? raw : undefined;
}

function asFiniteNumber(value: unknown): number | undefined {
  const numberValue = typeof value === "number"
    ? value
    : typeof value === "string" && value.trim().length > 0
      ? Number(value)
      : Number.NaN;
  return Number.isFinite(numberValue) ? numberValue : undefined;
}

function parseCoordinatePair(latitudeValue: unknown, longitudeValue: unknown): { latitude: number; longitude: number } | undefined {
  const latitude = asFiniteNumber(latitudeValue);
  const longitude = asFiniteNumber(longitudeValue);

  if (
    latitude === undefined
    || longitude === undefined
    || latitude < -90
    || latitude > 90
    || longitude < -180
    || longitude > 180
  ) {
    return undefined;
  }

  return { latitude, longitude };
}

function asSOSSource(value: unknown, fallback: SOSSource): SOSSource {
  const source = asString(value);
  return source && sosSources.has(source as SOSSource) ? source as SOSSource : fallback;
}

function serializeSOSEvent(row: SOSEventRow) {
  return {
    id: row.id,
    userId: row.user_id,
    venueId: row.venue_id,
    matchId: row.match_id,
    latitude: row.latitude,
    longitude: row.longitude,
    accuracyMeters: row.accuracy_meters,
    source: row.source,
    message: row.message,
    status: row.status,
    createdAt: row.created_at.toISOString()
  };
}

async function getActiveMatchIdsBetween(userAId: string, userBId: string): Promise<string[]> {
  const result = await query<MatchIdRow>(
    `
      SELECT id
      FROM matches
      WHERE unmatched_at IS NULL
        AND (
          (user_a_id = $1 AND user_b_id = $2)
          OR (user_a_id = $2 AND user_b_id = $1)
        )
    `,
    [userAId, userBId]
  );

  return result.rows.map((row) => row.id);
}

export async function safetyRoutes(app: FastifyInstance): Promise<void> {
  app.get("/safety/hidden-users", { preHandler: authenticate }, async (request) => {
    const result = await query<HiddenUserRow>(
      `
        SELECT hidden.user_id
        FROM (
          SELECT blocked_id AS user_id
          FROM blocks
          WHERE blocker_id = $1

          UNION

          SELECT blocker_id AS user_id
          FROM blocks
          WHERE blocked_id = $1

          UNION

          SELECT reported_id AS user_id
          FROM reports
          WHERE reporter_id = $1

          UNION

          SELECT reporter_id AS user_id
          FROM reports
          WHERE reported_id = $1
        ) hidden
        WHERE hidden.user_id <> $1
      `,
      [request.auth.userId]
    );

    return { userIds: result.rows.map((row) => row.user_id) };
  });

  app.post<{
    Body: {
      venueId?: unknown;
      matchId?: unknown;
      latitude?: unknown;
      longitude?: unknown;
      accuracyMeters?: unknown;
      source?: unknown;
      message?: unknown;
    };
  }>("/safety/sos", { preHandler: authenticate }, async (request, reply) => {
    const venueId = asUuid(request.body?.venueId);
    const matchId = asUuid(request.body?.matchId);

    if (request.body?.venueId && !venueId) {
      return sendError(reply, 400, "venueId must be a valid UUID");
    }

    if (request.body?.matchId && !matchId) {
      return sendError(reply, 400, "matchId must be a valid UUID");
    }

    if (matchId) {
      const match = await query(
        `
          SELECT 1
          FROM matches
          WHERE id = $1
            AND unmatched_at IS NULL
            AND (user_a_id = $2 OR user_b_id = $2)
        `,
        [matchId, request.auth.userId]
      );

      if (match.rowCount === 0) {
        return sendError(reply, 404, "Match not found");
      }
    }

    if (venueId) {
      const venue = await query("SELECT 1 FROM venues WHERE id = $1 AND is_active = true", [venueId]);
      if (venue.rowCount === 0) {
        return sendError(reply, 404, "Venue not found");
      }
    }

    const activeCheckIn = venueId
      ? null
      : await query<{ venue_id: string }>(
        `
          SELECT venue_id
          FROM checkins
          WHERE user_id = $1
            AND checked_out_at IS NULL
          ORDER BY checked_in_at DESC
          LIMIT 1
        `,
        [request.auth.userId]
      );

    const resolvedVenueId = venueId ?? activeCheckIn?.rows[0]?.venue_id ?? null;
    const coordinates = parseCoordinatePair(request.body?.latitude, request.body?.longitude);
    const accuracyMeters = asFiniteNumber(request.body?.accuracyMeters);
    const fallbackSource: SOSSource = matchId ? "chat" : resolvedVenueId ? "venue" : "app";
    const source = asSOSSource(request.body?.source, fallbackSource);
    const message = asString(request.body?.message)?.trim().slice(0, 500) || null;

    const result = await query<SOSEventRow>(
      `
        INSERT INTO sos_events(
          user_id,
          venue_id,
          match_id,
          latitude,
          longitude,
          accuracy_meters,
          source,
          message
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING id, user_id, venue_id, match_id, latitude, longitude,
                  accuracy_meters, source, message, status, created_at
      `,
      [
        request.auth.userId,
        resolvedVenueId,
        matchId ?? null,
        coordinates?.latitude ?? null,
        coordinates?.longitude ?? null,
        accuracyMeters ?? null,
        source,
        message
      ]
    );

    const event = result.rows[0];
    app.log.warn(
      {
        sosEventId: event.id,
        userId: request.auth.userId,
        venueId: event.venue_id,
        matchId: event.match_id,
        source: event.source
      },
      "SOS event recorded"
    );

    return {
      ok: true,
      emergencyNumber: "112",
      event: serializeSOSEvent(event)
    };
  });

  app.post<{ Body: { blockedUserId?: unknown } }>(
    "/blocks",
    { preHandler: authenticate },
    async (request, reply) => {
      const blockedUserId = asUuid(request.body?.blockedUserId);
      if (!blockedUserId) {
        return sendError(reply, 400, "blockedUserId must be a valid UUID");
      }

      if (blockedUserId === request.auth.userId) {
        return sendError(reply, 400, "You cannot block yourself");
      }

      const activeMatchIds = await getActiveMatchIdsBetween(request.auth.userId, blockedUserId);

      await withTransaction(async (client) => {
        await client.query(
          `
            INSERT INTO blocks(blocker_id, blocked_id)
            VALUES ($1, $2)
            ON CONFLICT DO NOTHING
          `,
          [request.auth.userId, blockedUserId]
        );
        await client.query(
          `
            UPDATE matches
            SET unmatched_at = now()
            WHERE unmatched_at IS NULL
              AND (
                (user_a_id = $1 AND user_b_id = $2)
                OR (user_a_id = $2 AND user_b_id = $1)
              )
          `,
          [request.auth.userId, blockedUserId]
        );
      });

      for (const activeMatchId of activeMatchIds) {
        broadcastToUser(request.auth.userId, {
          type: "match.unmatched",
          matchId: activeMatchId
        });
        broadcastToUser(blockedUserId, {
          type: "match.unmatched",
          matchId: activeMatchId
        });
      }

      broadcastToUser(request.auth.userId, { type: "safety.hidden_users_updated" });
      broadcastToUser(blockedUserId, { type: "safety.hidden_users_updated" });

      return { ok: true };
    }
  );

  app.post<{
    Body: {
      reportedUserId?: unknown;
      matchId?: unknown;
      category?: unknown;
      reason?: unknown;
      details?: unknown;
    };
  }>("/reports", { preHandler: authenticate }, async (request, reply) => {
    const reportedUserId = asUuid(request.body?.reportedUserId);
    const matchId = asUuid(request.body?.matchId);
    const category = asString(request.body?.category) === "spam" ? "spam" : "safety";
    const reason = asString(request.body?.reason)?.trim();
    if (!reportedUserId || !reason) {
      return sendError(reply, 400, "reportedUserId and reason are required");
    }

    if (reportedUserId === request.auth.userId) {
      return sendError(reply, 400, "You cannot report yourself");
    }

    if (request.body?.matchId && !matchId) {
      return sendError(reply, 400, "matchId must be a valid UUID");
    }

    if (matchId) {
      const match = await query(
        `
          SELECT 1
          FROM matches
          WHERE id = $1
            AND (user_a_id = $2 OR user_b_id = $2)
            AND (user_a_id = $3 OR user_b_id = $3)
        `,
        [matchId, request.auth.userId, reportedUserId]
      );

      if (match.rowCount === 0) {
        return sendError(reply, 404, "Match not found");
      }
    }

    const activeMatchIds = await getActiveMatchIdsBetween(request.auth.userId, reportedUserId);

    await withTransaction(async (client) => {
      await client.query(
        `
          INSERT INTO reports(reporter_id, reported_id, match_id, category, reason, details)
          VALUES ($1, $2, $3, $4, $5, $6)
        `,
        [
          request.auth.userId,
          reportedUserId,
          matchId ?? null,
          category,
          reason.slice(0, 120),
          asString(request.body?.details)?.trim().slice(0, 1000) ?? null
        ]
      );
      await client.query(
        `
          INSERT INTO blocks(blocker_id, blocked_id)
          VALUES ($1, $2)
          ON CONFLICT DO NOTHING
        `,
        [request.auth.userId, reportedUserId]
      );
      await client.query(
        `
          UPDATE matches
          SET unmatched_at = now()
          WHERE unmatched_at IS NULL
            AND (
              (user_a_id = $1 AND user_b_id = $2)
              OR (user_a_id = $2 AND user_b_id = $1)
            )
        `,
        [request.auth.userId, reportedUserId]
      );
      await client.query(
        `
          UPDATE users
          SET is_flagged = true
          WHERE id = $1
            AND (
              SELECT count(*)
              FROM reports
              WHERE reported_id = $1
            ) >= 3
        `,
        [reportedUserId]
      );
    });

    for (const activeMatchId of activeMatchIds) {
      broadcastToUser(request.auth.userId, {
        type: "match.unmatched",
        matchId: activeMatchId
      });
      broadcastToUser(reportedUserId, {
        type: "match.unmatched",
        matchId: activeMatchId
      });
    }

    broadcastToUser(request.auth.userId, { type: "safety.hidden_users_updated" });
    broadcastToUser(reportedUserId, { type: "safety.hidden_users_updated" });

    return { ok: true };
  });
}
