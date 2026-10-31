import { FastifyInstance } from "fastify";
import { query, withTransaction } from "../db/pool.js";
import { authenticate } from "../plugins/auth.js";
import { broadcastToUser } from "../realtime/chatHub.js";
import { withSignedPhotoUrls } from "../services/profilePhotoStorage.js";
import { asString, sendError } from "../utils/http.js";
import { PhotoRow, PromptRow, serializeProfile, UserRow } from "../utils/serializers.js";

type VenueRow = {
  id: string;
  name: string;
  city: string;
  neighborhood: string;
  vibe: string | null;
  music: string | null;
  symbol_name: string | null;
  gradient_hex: string[] | null;
  latitude: number | null;
  longitude: number | null;
  checkin_radius_meters: number;
  occupancy: string;
};

type VenueLocationRow = Pick<
  VenueRow,
  "id" | "name" | "latitude" | "longitude" | "checkin_radius_meters"
>;

function serializeVenue(row: VenueRow) {
  return {
    id: row.id,
    name: row.name,
    city: row.city,
    neighborhood: row.neighborhood,
    vibe: row.vibe ?? "",
    music: row.music ?? "",
    symbolName: row.symbol_name ?? "building.2.fill",
    gradientHex: row.gradient_hex ?? [],
    latitude: row.latitude,
    longitude: row.longitude,
    checkinRadiusMeters: row.checkin_radius_meters,
    occupancy: Number(row.occupancy)
  };
}

function asFiniteNumber(value: unknown): number | undefined {
  const numberValue = typeof value === "number" ? value : Number(value);
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

function distanceMeters(
  latitudeA: number,
  longitudeA: number,
  latitudeB: number,
  longitudeB: number
): number {
  const earthRadiusMeters = 6_371_000;
  const toRadians = (degrees: number) => degrees * Math.PI / 180;
  const deltaLatitude = toRadians(latitudeB - latitudeA);
  const deltaLongitude = toRadians(longitudeB - longitudeA);
  const startLatitude = toRadians(latitudeA);
  const endLatitude = toRadians(latitudeB);

  const haversine = Math.sin(deltaLatitude / 2) ** 2
    + Math.cos(startLatitude) * Math.cos(endLatitude) * Math.sin(deltaLongitude / 2) ** 2;

  return 2 * earthRadiusMeters * Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine));
}

async function activeCheckedInUserIdsAtVenue(venueId: string): Promise<string[]> {
  const result = await query<{ user_id: string }>(
    `
      SELECT DISTINCT c.user_id
      FROM checkins c
      JOIN users u ON u.id = c.user_id
      WHERE c.venue_id = $1
        AND c.checked_out_at IS NULL
        AND u.is_active = true
        AND u.deletion_scheduled_at IS NULL
    `,
    [venueId]
  );

  return result.rows.map((row) => row.user_id);
}

async function broadcastVenuePresenceChanged(
  venueIds: Iterable<string>,
  actorUserId: string,
  status: "checked_in" | "checked_out"
): Promise<void> {
  const uniqueVenueIds = Array.from(new Set(venueIds));

  await Promise.all(uniqueVenueIds.map(async (venueId) => {
    const recipients = await activeCheckedInUserIdsAtVenue(venueId);
    for (const userId of recipients) {
      broadcastToUser(userId, {
        type: "venue.presence_changed",
        venueId,
        userId: actorUserId,
        status
      });
    }
  }));
}

export async function venueRoutes(app: FastifyInstance): Promise<void> {
  app.get<{ Querystring: { city?: unknown } }>("/venues", { preHandler: authenticate }, async (request) => {
    const city = asString(request.query.city)?.trim();
    const cityFilter = city && city.length > 0 ? city : null;

    const result = await query<VenueRow>(`
      SELECT v.id, v.name, v.city, v.neighborhood, v.vibe, v.music, v.symbol_name, v.gradient_hex,
             v.latitude, v.longitude, v.checkin_radius_meters,
             count(c.id) FILTER (WHERE c.checked_out_at IS NULL AND u.id IS NOT NULL)::text AS occupancy
      FROM venues v
      LEFT JOIN checkins c ON c.venue_id = v.id AND c.checked_out_at IS NULL
      LEFT JOIN users u ON u.id = c.user_id
        AND u.is_active = true
        AND u.deletion_scheduled_at IS NULL
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
            AND NOT EXISTS (
              SELECT 1 FROM matches m
              WHERE (m.user_a_id = $2 AND m.user_b_id = u.id)
                 OR (m.user_a_id = u.id AND m.user_b_id = $2)
            )
      WHERE v.is_active = true
        AND ($1::text IS NULL OR v.city = $1)
      GROUP BY v.id
      ORDER BY v.city, v.name
    `, [cityFilter, request.auth.userId]);

    return { venues: result.rows.map(serializeVenue) };
  });

  app.get<{ Params: { id: string } }>(
    "/venues/:id/roster",
    { preHandler: authenticate },
    async (request) => {
      const usersResult = await query<UserRow>(
        `
          SELECT u.id, u.name, u.age, u.bio, u.profession, u.gender, u.height,
                 u.interests, u.is_verified, u.is_ghost_mode, u.looking_for
          FROM checkins c
          JOIN users u ON u.id = c.user_id
          WHERE c.venue_id = $1
            AND c.checked_out_at IS NULL
            AND u.id != $2
            AND u.is_active = true
            AND u.deletion_scheduled_at IS NULL
            AND u.is_flagged = false
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
            AND NOT EXISTS (
              SELECT 1 FROM matches m
              WHERE (m.user_a_id = $2 AND m.user_b_id = u.id)
                 OR (m.user_a_id = u.id AND m.user_b_id = $2)
            )
          ORDER BY c.checked_in_at DESC
        `,
        [request.params.id, request.auth.userId]
      );

      const roster = await Promise.all(
        usersResult.rows.map(async (user) => {
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

          return serializeProfile(
            user,
            promptsResult.rows,
            await withSignedPhotoUrls(photosResult.rows)
          );
        })
      );

      return { roster };
    }
  );

  app.post<{ Params: { id: string }; Body: { latitude?: unknown; longitude?: unknown } }>(
    "/venues/:id/checkin",
    { preHandler: authenticate },
    async (request, reply) => {
      const userLocation = parseCoordinatePair(request.body?.latitude, request.body?.longitude);

      if (!userLocation) {
        return sendError(reply, 400, "Current location is required to check in");
      }

      const venue = await query<VenueLocationRow>(
        `
          SELECT id, name, latitude, longitude, checkin_radius_meters
          FROM venues
          WHERE id = $1
            AND is_active = true
        `,
        [request.params.id]
      );
      if (venue.rowCount === 0) {
        return sendError(reply, 404, "Venue not found");
      }

      const venueRow = venue.rows[0];
      const venueLocation = parseCoordinatePair(venueRow.latitude, venueRow.longitude);
      const radiusMeters = Math.max(25, asFiniteNumber(venueRow.checkin_radius_meters) ?? 200);

      if (!venueLocation) {
        return sendError(reply, 500, "Venue location is not configured");
      }

      if (
        distanceMeters(
          userLocation.latitude,
          userLocation.longitude,
          venueLocation.latitude,
          venueLocation.longitude
        ) > radiusMeters
      ) {
        return sendError(reply, 403, `You need to be at ${venueRow.name} to check in.`);
      }

      const previousVenueIds = await withTransaction(async (client) => {
        const existingCheckins = await client.query<{ venue_id: string }>(
          `
            SELECT venue_id
            FROM checkins
            WHERE user_id = $1
              AND checked_out_at IS NULL
          `,
          [request.auth.userId]
        );

        await client.query(
          "UPDATE checkins SET checked_out_at = now() WHERE user_id = $1 AND checked_out_at IS NULL",
          [request.auth.userId]
        );
        await client.query(
          "INSERT INTO checkins(user_id, venue_id) VALUES ($1, $2)",
          [request.auth.userId, request.params.id]
        );

        return existingCheckins.rows.map((row) => row.venue_id);
      });

      const previousOtherVenueIds = previousVenueIds.filter((venueId) => venueId !== request.params.id);
      if (previousOtherVenueIds.length > 0) {
        await broadcastVenuePresenceChanged(
          previousOtherVenueIds,
          request.auth.userId,
          "checked_out"
        );
      }
      await broadcastVenuePresenceChanged(
        [request.params.id],
        request.auth.userId,
        "checked_in"
      );

      return { ok: true };
    }
  );

  app.delete<{ Params: { id: string } }>(
    "/venues/:id/checkin",
    { preHandler: authenticate },
    async (request) => {
      const result = await query<{ venue_id: string }>(
        `
          UPDATE checkins
          SET checked_out_at = now()
          WHERE user_id = $1
            AND venue_id = $2
            AND checked_out_at IS NULL
          RETURNING venue_id
        `,
        [request.auth.userId, request.params.id]
      );

      if ((result.rowCount ?? 0) > 0) {
        await broadcastVenuePresenceChanged(
          result.rows.map((row) => row.venue_id),
          request.auth.userId,
          "checked_out"
        );
      }

      return { ok: true };
    }
  );
}
