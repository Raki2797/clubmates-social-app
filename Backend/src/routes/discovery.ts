import { FastifyInstance } from "fastify";
import { query, withTransaction } from "../db/pool.js";
import { authenticate } from "../plugins/auth.js";
import { broadcastToUser } from "../realtime/chatHub.js";
import {
  signedProfilePhotoUrl,
  withSignedPhotoUrls
} from "../services/profilePhotoStorage.js";
import {
  acceptInvite,
  expirePendingInvites,
  findActivePairMatch,
  findIncomingPendingInvite,
  findOutgoingPendingInvite,
  lockUserPair
} from "../services/inviteMatchState.js";
import { asString, sendError } from "../utils/http.js";
import {
  PhotoRow,
  PromptRow,
  serializeCompactProfile,
  serializeProfile,
  UserRow
} from "../utils/serializers.js";

type SwipeDirection = "like" | "nope" | "superlike";

function isSwipeDirection(value: unknown): value is SwipeDirection {
  return value === "like" || value === "nope" || value === "superlike";
}

async function compactProfileForUser(userId: string) {
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

export async function discoveryRoutes(app: FastifyInstance): Promise<void> {
  app.get("/swipes/incoming", { preHandler: authenticate }, async (request) => {
    const result = await query<UserRow & {
      direction: SwipeDirection;
      created_at: Date;
      venue_id: string | null;
    }>(
      `
        SELECT DISTINCT ON (u.id)
          u.id, u.name, u.age, u.bio, u.profession, u.gender, u.height,
          u.interests, u.is_verified, u.looking_for,
          s.direction, s.created_at, s.venue_id
        FROM swipes s
        JOIN users u ON u.id = s.actor_id
        WHERE s.target_id = $1
          AND s.direction IN ('like', 'superlike')
          AND u.is_active = true
          AND u.deletion_scheduled_at IS NULL
          AND u.profile_completed = true
          AND NOT EXISTS (
            SELECT 1 FROM swipes mine
            WHERE mine.actor_id = $1
              AND mine.target_id = u.id
              AND mine.venue_id = s.venue_id
          )
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
            WHERE ((m.user_a_id = $1 AND m.user_b_id = u.id)
                OR (m.user_a_id = u.id AND m.user_b_id = $1))
              AND m.unmatched_at IS NULL
          )
        ORDER BY u.id, s.created_at DESC
      `,
      [request.auth.userId]
    );

    const swipes = await Promise.all(result.rows.map(async (row) => {
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
        profile: serializeProfile(row, promptsResult.rows, await withSignedPhotoUrls(photosResult.rows)),
        direction: row.direction,
        createdAt: row.created_at,
        venueId: row.venue_id
      };
    }));

    return { swipes };
  });

  app.get<{ Params: { id: string } }>(
    "/venues/:id/discover",
    { preHandler: authenticate },
    async (request) => {
      // Fetch requesting user's preferences first
      const meResult = await query<{
        pref_age_min: number;
        pref_age_max: number;
        pref_genders: string[];
        pref_height_min: number;
        pref_height_max: number;
        pref_verified_only: boolean;
      }>(
        `SELECT pref_age_min, pref_age_max, pref_genders,
                pref_height_min, pref_height_max, pref_verified_only
         FROM users WHERE id = $1`,
        [request.auth.userId]
      );
      const me = meResult.rows[0];

      const result = await query<UserRow & {
        has_super_liked_me: boolean;
      }>(
        `
          SELECT u.id, u.name, u.age, u.bio, u.profession, u.gender, u.height,
                 u.interests, u.is_verified, u.is_ghost_mode, u.looking_for,
                 (s.direction = 'superlike') AS has_super_liked_me
          FROM users u
          JOIN checkins c ON c.user_id = u.id
            AND c.venue_id = $1
            AND c.checked_out_at IS NULL
          LEFT JOIN swipes s ON s.actor_id = u.id
            AND s.target_id = $2
            AND s.venue_id = $1
            AND s.direction = 'superlike'
          WHERE u.id != $2
            AND u.is_active = true
            AND u.deletion_scheduled_at IS NULL
            AND u.is_flagged = false
            AND u.profile_completed = true
            AND u.is_ghost_mode = false
            AND u.age BETWEEN $3 AND $4
            AND u.height BETWEEN $5 AND $6
            AND ($7::text[] = '{}' OR u.gender = ANY($7::text[]))
            AND ($8 = false OR u.is_verified = true)
            AND NOT EXISTS (
              SELECT 1 FROM swipes
              WHERE actor_id = $2 AND target_id = u.id AND venue_id = $1
            )
            AND NOT EXISTS (
              SELECT 1 FROM treat_invites i
              WHERE i.sender_id = $2
                AND i.receiver_id = u.id
                AND i.venue_id = $1
                AND i.status IN ('pending', 'accepted')
                AND (i.status != 'pending' OR i.expires_at > now())
            )
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
            AND NOT EXISTS (
              SELECT 1 FROM matches m
              WHERE (m.user_a_id = $2 AND m.user_b_id = u.id)
                 OR (m.user_a_id = u.id AND m.user_b_id = $2)
            )
          ORDER BY c.checked_in_at DESC
          LIMIT 20
        `,
        [
          request.params.id,
          request.auth.userId,
          me?.pref_age_min ?? 18,
          me?.pref_age_max ?? 60,
          me?.pref_height_min ?? 100,
          me?.pref_height_max ?? 250,
          me?.pref_genders ?? [],
          me?.pref_verified_only ?? false
        ]
      );

      const profiles = await Promise.all(
        result.rows.map(async (user) => {
          const [promptsResult, photosResult] = await Promise.all([
            query<PromptRow>(
              "SELECT id, question, answer, position FROM profile_prompts WHERE user_id = $1 ORDER BY position",
              [user.id]
            ),
            query<PhotoRow>(
              "SELECT id, storage_key, cdn_url, position FROM profile_photos WHERE user_id = $1 ORDER BY position",
              [user.id]
            )
          ]);

          return {
            ...serializeProfile(
              user,
              promptsResult.rows,
              await withSignedPhotoUrls(photosResult.rows)
            ),
            hasSuperLikedMe: user.has_super_liked_me
          };
        })
      );

      return { profiles };
    }
  );

  app.post<{
    Body: {
      targetUserId?: string;
      venueId?: string;
      direction?: string;
    };
  }>("/swipes", { preHandler: authenticate }, async (request, reply) => {
    const targetUserId = asString(request.body?.targetUserId);
    const venueId = asString(request.body?.venueId);
    const direction = request.body?.direction;

    if (!targetUserId || !venueId || !isSwipeDirection(direction)) {
      return sendError(reply, 400, "targetUserId, venueId, and valid direction are required");
    }
    request.log.info(
      {
        trace: "swipe.request",
        actorUserId: request.auth.userId,
        targetUserId,
        venueId,
        direction
      },
      "[SwipeTrace] Swipe request received"
    );

    const target = await query(
      `
        SELECT 1
        FROM users u
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

    const transition = await withTransaction(async (client) => {
      await lockUserPair(client, request.auth.userId, targetUserId);
      await expirePendingInvites(client, request.auth.userId, targetUserId);

      if (direction === "like" || direction === "superlike") {
        const activeMatchId = await findActivePairMatch(
          client,
          request.auth.userId,
          targetUserId
        );
        if (activeMatchId) {
          return {
            isMatch: true,
            matchId: activeMatchId,
            acceptedInviteId: null,
            alreadyMatched: true
          };
        }

        const incomingInvite = await findIncomingPendingInvite(
          client,
          request.auth.userId,
          targetUserId
        );
        if (incomingInvite) {
          const matchId = await acceptInvite(client, incomingInvite, "accepted_by_like");
          return {
            isMatch: true,
            matchId,
            acceptedInviteId: incomingInvite.id,
            alreadyMatched: false
          };
        }

        const outgoingInvite = await findOutgoingPendingInvite(
          client,
          request.auth.userId,
          targetUserId
        );
        if (outgoingInvite) {
          return {
            isMatch: false,
            matchId: null,
            acceptedInviteId: null,
            alreadyMatched: false
          };
        }
      }

      const swipe = await client.query<{ is_match: boolean; match_id: string | null }>(
        "SELECT * FROM record_swipe($1, $2, $3, $4)",
        [request.auth.userId, targetUserId, venueId, direction]
      );
      const row = swipe.rows[0];
      return {
        isMatch: row?.is_match ?? false,
        matchId: row?.match_id ?? null,
        acceptedInviteId: null,
        alreadyMatched: false
      };
    });
    request.log.info(
      {
        trace: "swipe.transition",
        actorUserId: request.auth.userId,
        targetUserId,
        direction,
        isMatch: transition.isMatch,
        matchId: transition.matchId,
        alreadyMatched: transition.alreadyMatched,
        acceptedInviteId: transition.acceptedInviteId
      },
      "[SwipeTrace] Swipe transaction completed"
    );

    if (transition.acceptedInviteId) {
      const acceptedEvent = {
        type: "invite.accepted",
        inviteId: transition.acceptedInviteId,
        matchId: transition.matchId,
        status: "accepted_by_like",
        venueId,
        createdAt: new Date().toISOString()
      };
      const [actorProfile, targetProfile] = await Promise.all([
        compactProfileForUser(request.auth.userId),
        compactProfileForUser(targetUserId)
      ]);
      broadcastToUser(request.auth.userId, {
        ...acceptedEvent,
        profile: targetProfile
      });
      broadcastToUser(targetUserId, {
        ...acceptedEvent,
        profile: actorProfile
      });
    } else if (!transition.alreadyMatched && (direction === "like" || direction === "superlike")) {
      const actorProfile = await compactProfileForUser(request.auth.userId);
      if (actorProfile) {
        const deliveredCount = broadcastToUser(targetUserId, {
          type: "swipe.received",
          profile: actorProfile,
          direction,
          isMatch: transition.isMatch,
          matchId: transition.matchId,
          venueId
        });
        request.log.info(
          {
            trace: "swipe.broadcast",
            actorUserId: request.auth.userId,
            targetUserId,
            eventType: "swipe.received",
            deliveredCount
          },
          "[SwipeTrace] Swipe event broadcast"
        );
      } else {
        request.log.warn(
          {
            trace: "swipe.broadcast",
            actorUserId: request.auth.userId,
            targetUserId
          },
          "[SwipeTrace] Actor profile unavailable; swipe event not broadcast"
        );
      }
    } else {
      request.log.info(
        {
          trace: "swipe.broadcast.skipped",
          actorUserId: request.auth.userId,
          targetUserId,
          direction,
          alreadyMatched: transition.alreadyMatched,
          acceptedInviteId: transition.acceptedInviteId
        },
        "[SwipeTrace] Direct swipe event broadcast skipped"
      );
    }

    return {
      isMatch: transition.isMatch,
      matchId: transition.matchId
    };
  });

  app.delete<{ Params: { targetUserId: string; venueId: string } }>(
    "/swipes/:targetUserId/:venueId",
    { preHandler: authenticate },
    async (request) => {
      const result = await query(
        "DELETE FROM swipes WHERE actor_id = $1 AND target_id = $2 AND venue_id = $3",
        [request.auth.userId, request.params.targetUserId, request.params.venueId]
      );
      if ((result.rowCount ?? 0) > 0) {
        const deliveredCount = broadcastToUser(request.params.targetUserId, {
          type: "swipe.withdrawn",
          userId: request.auth.userId,
          venueId: request.params.venueId
        });
        request.log.info(
          {
            trace: "swipe.withdrawn",
            actorUserId: request.auth.userId,
            targetUserId: request.params.targetUserId,
            venueId: request.params.venueId,
            deliveredCount
          },
          "[SwipeTrace] Swipe withdrawal broadcast"
        );
      }
      return { ok: true };
    }
  );
}
