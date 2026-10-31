import type { FastifyInstance, FastifyRequest } from "fastify";
import { createHash, randomUUID } from "node:crypto";
import { DbClient, query, withTransaction } from "../db/pool.js";
import { authenticate } from "../plugins/auth.js";
import {
  authenticatedPhotoUrl,
  authenticatedVerificationSelfieUrl,
  deleteProfilePhotoObjects,
  signedProfilePhotoUrl,
  signedVerificationSelfieUrl,
  uploadProfilePhotoObject,
  uploadVerificationSelfieObject,
  withSignedPhotoUrls
} from "../services/profilePhotoStorage.js";
import {
  compareEmbeddingToEmbedding,
  extractFaceEmbedding,
  FaceComparisonError,
  verifyUserAgainstProfilePhotos
} from "../services/faceVerification.js";
import { enqueueEmbeddingJob, enqueueSelfieEmbeddingJob } from "../services/embeddingWorker.js";
import { asString, asStringArray, sendError } from "../utils/http.js";
import { PhotoRow, PromptRow, serializeProfile, UserRow } from "../utils/serializers.js";
import { env } from "../config/env.js";

type PromptInput = {
  id?: string;
  question?: string;
  answer?: string;
};

type AccountDeletionRow = {
  phone_e164: string;
  deletion_scheduled_at: Date;
};

type SelfieEmbeddingPresenceRow = {
  face_embedding: number[] | null;
};

const maxProfilePhotoBytes = 5 * 1024 * 1024;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const allowedPhotoTypes = new Map([
  ["image/jpeg", "jpg"],
  ["image/png", "png"],
  ["image/webp", "webp"]
]);
const maxProfilePhotos = 6;

function sha256Hex(buffer: Buffer): string {
  return createHash("sha256").update(buffer).digest("hex");
}

function photoExtension(mimeType: string, filename?: string): string | undefined {
  const fromMime = allowedPhotoTypes.get(mimeType.toLowerCase());
  if (fromMime) {
    return fromMime;
  }

  if (mimeType.toLowerCase() !== "application/octet-stream" || !filename) {
    return undefined;
  }

  const extension = filename.split(".").pop()?.toLowerCase();
  if (extension === "jpg" || extension === "jpeg") {
    return "jpg";
  }
  if (extension === "png" || extension === "webp") {
    return extension;
  }

  return undefined;
}

function parsePhotoPosition(value: unknown): number {
  if (typeof value === "number") {
    return value;
  }

  if (typeof value === "string" && value.trim()) {
    return Number(value);
  }

  return 0;
}

function isValidPhotoPosition(position: number): boolean {
  return Number.isInteger(position) && position >= 0 && position < maxProfilePhotos;
}

async function readMultipartImagePair(request: FastifyRequest) {
  const imageBuffers = new Map<string, Buffer>();

  for await (const part of request.parts()) {
    if (part.type !== "file") {
      continue;
    }

    if (part.fieldname !== "image1" && part.fieldname !== "image2") {
      request.log.info(
        { fieldname: part.fieldname, filename: part.filename },
        "Ignoring unexpected multipart file field"
      );
      continue;
    }

    const chunks: Buffer[] = [];
    for await (const chunk of part.file) {
      chunks.push(chunk);
    }

    const buffer = Buffer.concat(chunks);
    imageBuffers.set(part.fieldname, buffer);
    request.log.info(
      {
        fieldname: part.fieldname,
        filename: part.filename,
        mimetype: part.mimetype,
        bytes: buffer.length
      },
      "Received face verification image"
    );
  }

  return {
    image1: imageBuffers.get("image1"),
    image2: imageBuffers.get("image2")
  };
}

function storageUrl(storageKey: string): string | undefined {
  return authenticatedPhotoUrl(storageKey);
}

function selfieStorageUrl(storageKey: string): string | undefined {
  return authenticatedVerificationSelfieUrl(storageKey);
}

async function reverifyAfterProfilePhotoSetChange(
  userId: string,
  logger: FastifyRequest["log"]
): Promise<void> {
  const selfie = await query<SelfieEmbeddingPresenceRow>(
    "SELECT face_embedding FROM users WHERE id = $1 LIMIT 1",
    [userId]
  );
  const embedding = selfie.rows[0]?.face_embedding;
  if (!Array.isArray(embedding) || embedding.length === 0) {
    return;
  }

  await verifyUserAgainstProfilePhotos(userId, logger);
}

async function fetchProfile(userId: string, includePhone = true) {
  const user = await query<UserRow>(
    `
      SELECT id, phone_e164, name, age, bio, profession, gender, height,
             interests, is_verified, is_ghost_mode, profile_completed, verification_selfie_url,
             verification_failure_reason, verification_mismatched_photo_ids,
             looking_for, pref_age_min, pref_age_max, pref_genders,
             pref_height_min, pref_height_max, pref_verified_only,
             notif_enabled, notif_new_match, notif_new_message,
             notif_liked_you, notif_super_like, notif_venue_activity
      FROM users
      WHERE id = $1
        AND is_active = true
        AND deletion_scheduled_at IS NULL
    `,
    [userId]
  );

  const userRow = user.rows[0];
  if (!userRow) {
    return undefined;
  }

  const [prompts, photos] = await Promise.all([
    query<PromptRow>(
      "SELECT id, question, answer, position FROM profile_prompts WHERE user_id = $1 ORDER BY position",
      [userId]
    ),
    query<PhotoRow>(
      "SELECT id, storage_key, cdn_url, position FROM profile_photos WHERE user_id = $1 ORDER BY position",
      [userId]
    )
  ]);

  const signedSelfieUrl = userRow.verification_selfie_url
    ? await signedVerificationSelfieUrl(userRow.verification_selfie_url)
    : null;

  const profileUser = {
    ...userRow,
    phone_e164: includePhone ? userRow.phone_e164 : undefined,
    verification_selfie_url: signedSelfieUrl ?? userRow.verification_selfie_url
  };

  return serializeProfile(
    profileUser,
    prompts.rows,
    await withSignedPhotoUrls(photos.rows)
  );
}

async function replacePrompts(client: DbClient, userId: string, prompts: PromptInput[] | undefined): Promise<void> {
  if (!prompts) {
    return;
  }

  await client.query("DELETE FROM profile_prompts WHERE user_id = $1", [userId]);
  for (const [index, prompt] of prompts.slice(0, 3).entries()) {
    if (!prompt.question || !prompt.answer) {
      continue;
    }

    await client.query(
      `
        INSERT INTO profile_prompts(user_id, question, answer, position)
        VALUES ($1, $2, $3, $4)
      `,
      [userId, prompt.question.trim(), prompt.answer.trim(), index]
    );
  }
}

export async function userRoutes(app: FastifyInstance): Promise<void> {
  app.get<{ Params: { id: string } }>("/users/:id/profile", { preHandler: authenticate }, async (request, reply) => {
    const targetUserId = request.params.id;
    if (targetUserId === request.auth.userId) {
      const me = await fetchProfile(request.auth.userId, false);
      if (!me) {
        return sendError(reply, 404, "User not found");
      }
      return { user: me };
    }

    const visibility = await query<{ visible: boolean }>(
      `
        SELECT EXISTS (
          SELECT 1
          FROM users target
          WHERE target.id = $1
            AND target.is_active = true
            AND target.deletion_scheduled_at IS NULL
            AND target.is_flagged = false
            AND target.profile_completed = true
            AND (
              EXISTS (
                SELECT 1
                FROM checkins me_checkin
                JOIN checkins target_checkin
                  ON target_checkin.venue_id = me_checkin.venue_id
                 AND target_checkin.checked_out_at IS NULL
                WHERE me_checkin.user_id = $2
                  AND me_checkin.checked_out_at IS NULL
                  AND target_checkin.user_id = target.id
                  AND target.is_ghost_mode = false
              )
              OR EXISTS (
                SELECT 1
                FROM matches active_match
                WHERE ((active_match.user_a_id = $2 AND active_match.user_b_id = target.id)
                    OR (active_match.user_a_id = target.id AND active_match.user_b_id = $2))
                  AND active_match.unmatched_at IS NULL
                  AND active_match.deleted_at IS NULL
              )
              OR EXISTS (
                SELECT 1
                FROM swipes incoming
                WHERE incoming.actor_id = target.id
                  AND incoming.target_id = $2
                  AND incoming.direction IN ('like', 'superlike')
                  AND NOT EXISTS (
                    SELECT 1
                    FROM swipes mine
                    WHERE mine.actor_id = $2
                      AND mine.target_id = target.id
                      AND mine.venue_id = incoming.venue_id
                  )
              )
            )
            AND NOT EXISTS (
              SELECT 1 FROM blocks
              WHERE (blocker_id = $2 AND blocked_id = target.id)
                 OR (blocker_id = target.id AND blocked_id = $2)
            )
            AND NOT EXISTS (
              SELECT 1 FROM reports
              WHERE (reporter_id = $2 AND reported_id = target.id)
                 OR (reporter_id = target.id AND reported_id = $2)
            )
            AND NOT EXISTS (
              SELECT 1
              FROM matches latest
              WHERE latest.id = (
                SELECT m.id
                FROM matches m
                WHERE (m.user_a_id = $2 AND m.user_b_id = target.id)
                   OR (m.user_a_id = target.id AND m.user_b_id = $2)
                ORDER BY m.created_at DESC
                LIMIT 1
              )
              AND latest.unmatched_at IS NOT NULL
            )
        ) AS visible
      `,
      [targetUserId, request.auth.userId]
    );

    if (!visibility.rows[0]?.visible) {
      return sendError(reply, 404, "Profile not available");
    }

    const profile = await fetchProfile(targetUserId, false);
    if (!profile) {
      return sendError(reply, 404, "Profile not available");
    }

    return { user: profile };
  });

  app.get("/users/me", { preHandler: authenticate }, async (request, reply) => {
    const profile = await fetchProfile(request.auth.userId);
    if (!profile) {
      return sendError(reply, 404, "User not found");
    }

    return { user: profile };
  });

  app.put<{
    Body: {
      name?: string;
      age?: number;
      bio?: string;
      profession?: string;
      gender?: string;
      height?: number;
      interests?: unknown;
      prompts?: PromptInput[];
      lookingFor?: string;
      preferences?: {
        ageMin?: number;
        ageMax?: number;
        genders?: unknown;
        heightMin?: number;
        heightMax?: number;
        verifiedOnly?: boolean;
      };
      notificationPreferences?: {
        enabled?: boolean;
        newMatch?: boolean;
        newMessage?: boolean;
        likedYou?: boolean;
        superLike?: boolean;
        venueActivity?: boolean;
      };
      isGhostMode?: boolean;
    };
  }>("/users/me", { preHandler: authenticate }, async (request, reply) => {
    const body = request.body ?? {};
    const name = asString(body.name)?.trim();
    const age = typeof body.age === "number" ? body.age : undefined;

    if (!name || !age) {
      return sendError(reply, 400, "name and age are required");
    }

    if (age < 18 || age > 120) {
      return sendError(reply, 400, "age must be between 18 and 120");
    }

    const prefs = body.preferences ?? {};
    const prefAgeMin = typeof prefs.ageMin === "number" ? Math.max(18, Math.min(prefs.ageMin, 120)) : 18;
    const prefAgeMax = typeof prefs.ageMax === "number" ? Math.max(18, Math.min(prefs.ageMax, 120)) : 60;
    const prefHeightMin = typeof prefs.heightMin === "number" ? Math.max(100, Math.min(prefs.heightMin, 250)) : 140;
    const prefHeightMax = typeof prefs.heightMax === "number" ? Math.max(100, Math.min(prefs.heightMax, 250)) : 220;
    const prefVerifiedOnly = typeof prefs.verifiedOnly === "boolean" ? prefs.verifiedOnly : false;
    const prefGenders = asStringArray(prefs.genders);

    const notif = body.notificationPreferences ?? {};
    const notifEnabled      = typeof notif.enabled      === "boolean" ? notif.enabled      : true;
    const notifNewMatch     = typeof notif.newMatch      === "boolean" ? notif.newMatch      : true;
    const notifNewMessage   = typeof notif.newMessage    === "boolean" ? notif.newMessage    : true;
    const notifLikedYou     = typeof notif.likedYou      === "boolean" ? notif.likedYou      : true;
    const notifSuperLike    = typeof notif.superLike     === "boolean" ? notif.superLike     : true;
    const notifVenueActivity = typeof notif.venueActivity === "boolean" ? notif.venueActivity : true;

    await withTransaction(async (client) => {
      await client.query(
        `
          UPDATE users
          SET name = $2,
              age = $3,
              bio = $4,
              profession = $5,
              gender = $6,
              height = $7,
              interests = $8,
              profile_completed = true,
              looking_for = $9,
              pref_age_min = $10,
              pref_age_max = $11,
              pref_genders = $12,
              pref_height_min = $13,
              pref_height_max = $14,
              pref_verified_only = $15,
              notif_enabled = $16,
              notif_new_match = $17,
              notif_new_message = $18,
              notif_liked_you = $19,
              notif_super_like = $20,
              notif_venue_activity = $21,
              is_ghost_mode = COALESCE($22::boolean, is_ghost_mode)
          WHERE id = $1
        `,
        [
          request.auth.userId,
          name,
          age,
          asString(body.bio)?.trim() ?? "",
          asString(body.profession)?.trim() ?? "",
          asString(body.gender)?.trim() ?? "",
          typeof body.height === "number" ? body.height : 0,
          asStringArray(body.interests),
          asString(body.lookingFor)?.trim() ?? "",
          prefAgeMin,
          prefAgeMax,
          prefGenders,
          prefHeightMin,
          prefHeightMax,
          prefVerifiedOnly,
          notifEnabled,
          notifNewMatch,
          notifNewMessage,
          notifLikedYou,
          notifSuperLike,
          notifVenueActivity,
          typeof body.isGhostMode === "boolean" ? body.isGhostMode : null
        ]
      );

      await replacePrompts(client, request.auth.userId, body.prompts);
    });

    const profile = await fetchProfile(request.auth.userId);
    return { user: profile };
  });

  app.patch<{
    Body: {
      name?: string;
      age?: number;
      bio?: string;
      profession?: string;
      gender?: string;
      height?: number;
      interests?: unknown;
      prompts?: PromptInput[];
      lookingFor?: string;
      preferences?: {
        ageMin?: number;
        ageMax?: number;
        genders?: unknown;
        heightMin?: number;
        heightMax?: number;
        verifiedOnly?: boolean;
      };
      notificationPreferences?: {
        enabled?: boolean;
        newMatch?: boolean;
        newMessage?: boolean;
        likedYou?: boolean;
        superLike?: boolean;
        venueActivity?: boolean;
      };
      isGhostMode?: boolean;
    };
  }>("/users/me", { preHandler: authenticate }, async (request, reply) => {
    const body = request.body ?? {};

    // Build dynamic SET clause — only touch columns that were sent
    const setClauses: string[] = [];
    const params: unknown[] = [request.auth.userId];

    function addParam(column: string, value: unknown): void {
      params.push(value);
      setClauses.push(`${column} = $${params.length}`);
    }

    const name = asString(body.name)?.trim();
    if (name !== undefined) {
      if (!name) return sendError(reply, 400, "name cannot be empty");
      addParam("name", name);
    }

    if (typeof body.age === "number") {
      if (body.age < 18 || body.age > 120) return sendError(reply, 400, "age must be between 18 and 120");
      addParam("age", body.age);
    }

    if (body.bio !== undefined) addParam("bio", asString(body.bio)?.trim() ?? "");
    if (body.profession !== undefined) addParam("profession", asString(body.profession)?.trim() ?? "");
    if (body.gender !== undefined) addParam("gender", asString(body.gender)?.trim() ?? "");
    if (typeof body.height === "number") addParam("height", body.height);
    if (body.interests !== undefined) addParam("interests", asStringArray(body.interests));
    if (body.lookingFor !== undefined) addParam("looking_for", asString(body.lookingFor)?.trim() ?? "");
    if (typeof body.isGhostMode === "boolean") addParam("is_ghost_mode", body.isGhostMode);

    if (body.preferences) {
      const p = body.preferences;
      if (typeof p.ageMin === "number") addParam("pref_age_min", Math.max(18, Math.min(p.ageMin, 120)));
      if (typeof p.ageMax === "number") addParam("pref_age_max", Math.max(18, Math.min(p.ageMax, 120)));
      if (p.genders !== undefined) addParam("pref_genders", asStringArray(p.genders));
      if (typeof p.heightMin === "number") addParam("pref_height_min", Math.max(100, Math.min(p.heightMin, 250)));
      if (typeof p.heightMax === "number") addParam("pref_height_max", Math.max(100, Math.min(p.heightMax, 250)));
      if (typeof p.verifiedOnly === "boolean") addParam("pref_verified_only", p.verifiedOnly);
    }

    if (body.notificationPreferences) {
      const n = body.notificationPreferences;
      if (typeof n.enabled === "boolean") addParam("notif_enabled", n.enabled);
      if (typeof n.newMatch === "boolean") addParam("notif_new_match", n.newMatch);
      if (typeof n.newMessage === "boolean") addParam("notif_new_message", n.newMessage);
      if (typeof n.likedYou === "boolean") addParam("notif_liked_you", n.likedYou);
      if (typeof n.superLike === "boolean") addParam("notif_super_like", n.superLike);
      if (typeof n.venueActivity === "boolean") addParam("notif_venue_activity", n.venueActivity);
    }

    if (setClauses.length === 0 && !body.prompts) {
      return sendError(reply, 400, "no fields to update");
    }

    await withTransaction(async (client) => {
      if (setClauses.length > 0) {
        await client.query(
          `UPDATE users SET ${setClauses.join(", ")} WHERE id = $1`,
          params
        );
      }
      await replacePrompts(client, request.auth.userId, body.prompts);
    });

    const profile = await fetchProfile(request.auth.userId);
    return { user: profile };
  });

  app.post<{ Querystring: { position?: string; clientPhotoId?: string } }>(
    "/users/me/photos",
    { preHandler: authenticate },
    async (request, reply) => {
      if (!request.isMultipart()) {
        return sendError(reply, 415, "Upload must be multipart/form-data with a photo file");
      }

      const position = parsePhotoPosition(request.query.position);
      if (!isValidPhotoPosition(position)) {
        return sendError(reply, 400, `position must be between 0 and ${maxProfilePhotos - 1}`);
      }

      const file = await request.file({
        limits: {
          fileSize: maxProfilePhotoBytes
        }
      });

      if (!file) {
        return sendError(reply, 400, "photo file is required");
      }

      const extension = photoExtension(file.mimetype, file.filename);
      if (!extension) {
        return sendError(reply, 400, "photo must be a JPEG, PNG, or WebP image");
      }

      const clientPhotoId = request.query.clientPhotoId;
      if (clientPhotoId !== undefined && !uuidPattern.test(clientPhotoId)) {
        return sendError(reply, 400, "clientPhotoId must be a valid UUID");
      }

      const existing = await query<PhotoRow>(
        `
          SELECT id, storage_key, cdn_url, position
          FROM profile_photos
          WHERE user_id = $1 AND position = $2
          LIMIT 1
        `,
        [request.auth.userId, position]
      );
      const previousPhoto = existing.rows[0];
      const photoId = previousPhoto?.id ?? clientPhotoId ?? randomUUID();
      const buffer = await file.toBuffer();
      const imageSha256 = sha256Hex(buffer);
      const objectVersion = previousPhoto ? `-${Date.now()}-${imageSha256.slice(0, 12)}` : "";
      const storageKey = `${request.auth.userId}/${photoId}${objectVersion}.${extension}`;
      const uploadStartedAt = Date.now();

      await uploadProfilePhotoObject(storageKey, buffer, file.mimetype);
      const fallbackUrl = storageUrl(storageKey);

      if (!fallbackUrl) {
        return sendError(reply, 503, "Storage is not configured");
      }

      const result = await query<PhotoRow>(
        `
          INSERT INTO profile_photos(id, user_id, storage_key, cdn_url, position, face_embeddings, face_count)
          VALUES ($1, $2, $3, $4, $5, NULL, NULL)
          ON CONFLICT (user_id, position)
          DO UPDATE SET storage_key = EXCLUDED.storage_key, cdn_url = EXCLUDED.cdn_url,
                        face_embeddings = NULL, face_count = NULL
          RETURNING id, storage_key, cdn_url, position
        `,
        [photoId, request.auth.userId, storageKey, fallbackUrl, position]
      );

      const savedPhotoId = result.rows[0]?.id;

      request.log.info(
        {
          photoId: savedPhotoId,
          position,
          bytes: buffer.length,
          imageSha256,
          durationMs: Date.now() - uploadStartedAt
        },
        "Profile photo upload completed"
      );

      if (savedPhotoId && fallbackUrl) {
        enqueueEmbeddingJob(savedPhotoId, fallbackUrl, request.log).catch(err => {
          request.log.warn({ err, photoId: savedPhotoId }, "Failed to enqueue embedding job");
        });
      }

      if (previousPhoto?.storage_key && previousPhoto.storage_key !== storageKey) {
        try {
          await deleteProfilePhotoObjects([previousPhoto.storage_key]);
        } catch (error) {
          request.log.warn({ err: error, storageKey: previousPhoto.storage_key }, "Failed to delete replaced profile photo");
        }
      }

      const savedPhoto = result.rows[0];
      return {
        photo: {
          id: savedPhotoId ?? savedPhoto.id,
          storageKey: savedPhoto.storage_key,
          cdnUrl: savedPhoto.cdn_url,
          position: savedPhoto.position
        }
      };
    }
  );

  app.delete<{ Params: { photoId: string } }>(
    "/users/me/photos/:photoId",
    { preHandler: authenticate },
    async (request) => {
      const deleted = await query<PhotoRow>(
        `
          DELETE FROM profile_photos
          WHERE user_id = $1 AND id = $2
          RETURNING id, storage_key, cdn_url, position
        `,
        [request.auth.userId, request.params.photoId]
      );

      const storageKey = deleted.rows[0]?.storage_key;
      if (storageKey) {
        try {
          await deleteProfilePhotoObjects([storageKey]);
        } catch (error) {
          request.log.warn({ err: error, storageKey }, "Failed to delete profile photo object");
        }

        await reverifyAfterProfilePhotoSetChange(request.auth.userId, request.log);
      }

      return { ok: true };
    }
  );

  app.put<{ Body: { order?: string[] } }>(
    "/users/me/photos/order",
    { preHandler: authenticate },
    async (request, reply) => {
      const order = request.body?.order;
      if (!Array.isArray(order)) {
        return sendError(reply, 400, "order must be an array of photo IDs");
      }
      if (order.length > maxProfilePhotos) {
        return sendError(reply, 400, `order cannot contain more than ${maxProfilePhotos} photo IDs`);
      }

      const uniqueOrder = [...new Set(order)];
      if (uniqueOrder.length !== order.length) {
        return sendError(reply, 400, "order cannot contain duplicate photo IDs");
      }

      const deletedStorageKeys = await withTransaction(async (client) => {
        const omitted = await client.query<{ storage_key: string }>(
          `
            DELETE FROM profile_photos
            WHERE user_id = $1
              AND NOT (id = ANY($2::uuid[]))
            RETURNING storage_key
          `,
          [request.auth.userId, uniqueOrder]
        );

        for (const [index, photoId] of order.entries()) {
          await client.query(
            "UPDATE profile_photos SET position = $3 WHERE user_id = $1 AND id = $2",
            [request.auth.userId, photoId, -(index + 1)]
          );
        }

        for (const [index, photoId] of order.entries()) {
          await client.query(
            "UPDATE profile_photos SET position = $3 WHERE user_id = $1 AND id = $2",
            [request.auth.userId, photoId, index]
          );
        }

        return omitted.rows.map((photo) => photo.storage_key);
      });

      if (deletedStorageKeys.length > 0) {
        try {
          await deleteProfilePhotoObjects(deletedStorageKeys);
        } catch (error) {
          request.log.warn({ err: error, storageKeys: deletedStorageKeys }, "Failed to delete omitted profile photo objects");
        }

        await reverifyAfterProfilePhotoSetChange(request.auth.userId, request.log);
      }

      return { ok: true };
    }
  );

  app.post<{ Body: { token?: string; platform?: string } }>(
    "/users/me/device-token",
    { preHandler: authenticate },
    async (request, reply) => {
      const token = asString(request.body?.token)?.trim();
      if (!token) {
        return sendError(reply, 400, "token is required");
      }

      await query(
        `
          INSERT INTO device_tokens(user_id, token, platform, updated_at)
          VALUES ($1, $2, $3, now())
          ON CONFLICT (user_id, token)
          DO UPDATE SET platform = EXCLUDED.platform, updated_at = now()
        `,
        [request.auth.userId, token, asString(request.body?.platform) ?? "apns"]
      );

      return { ok: true };
    }
  );

  // Extracts an ArcFace embedding from a single uploaded image and returns it.
  // The client stores the embedding locally and handles all comparison math.
  app.post(
    "/photos/extract-embedding",
    {
      preHandler: authenticate,
      bodyLimit: 20 * 1024 * 1024
    },
    async (request, reply) => {
      if (!request.isMultipart()) {
        return sendError(reply, 415, "Upload must be multipart/form-data with a photo file");
      }

      const file = await request.file();
      if (!file) {
        return sendError(reply, 400, "photo file is required");
      }

      const chunks: Buffer[] = [];
      for await (const chunk of file.file) { chunks.push(chunk); }
      const photoBuffer = Buffer.concat(chunks);

      request.log.info(
        { userId: request.auth.userId, photoBytes: photoBuffer.length },
        "[EmbedDebug] Extracting embedding from photo"
      );

      let embedding: number[];
      try {
        embedding = await extractFaceEmbedding(photoBuffer, request.log);
      } catch (error) {
        request.log.error({ err: error }, "[EmbedDebug] Extraction failed");
        if (error instanceof FaceComparisonError) {
          return sendError(reply, 422, error.message);
        }
        throw error;
      }

      const norm = Math.sqrt(embedding.reduce((s, v) => s + v * v, 0));
      request.log.info(
        {
          dims: embedding.length,
          norm: norm.toFixed(6),
          first5: embedding.slice(0, 5),
          last5: embedding.slice(-5),
        },
        "[EmbedDebug] Embedding extracted"
      );

      return {
        ok: true,
        embedding,
        model: env.faceVerification?.model ?? "ArcFace",
        dims: embedding.length,
      };
    }
  );

  app.post(
    "/photos/compare",
    {
      preHandler: authenticate,
      bodyLimit: 40 * 1024 * 1024
    },
    async (request, reply) => {
      if (!request.isMultipart()) {
        return sendError(reply, 415, "Upload must be multipart/form-data with image1 and image2 files");
      }

      const { image1, image2 } = await readMultipartImagePair(request);
      if (!image1 || !image2) {
        return sendError(reply, 400, "image1 and image2 files are required");
      }

      try {
        const [embedding1, embedding2] = await Promise.all([
          extractFaceEmbedding(image1, request.log),
          extractFaceEmbedding(image2, request.log)
        ]);

        return {
          ok: true,
          verification: compareEmbeddingToEmbedding(embedding1, embedding2)
        };
      } catch (error) {
        if (error instanceof FaceComparisonError) {
          return sendError(reply, 422, error.message);
        }
        throw error;
      }
    }
  );

  app.post(
    "/users/me/verification-selfie",
    { preHandler: authenticate },
    async (request, reply) => {
      if (!env.supabase) {
        return sendError(reply, 503, "Storage is not configured");
      }

      const file = await request.file({ limits: { fileSize: maxProfilePhotoBytes } });
      if (!file) {
        return sendError(reply, 400, "selfie file is required");
      }

      const chunks: Buffer[] = [];
      for await (const chunk of file.file) {
        chunks.push(chunk);
      }
      if (file.file.truncated) {
        return sendError(reply, 413, "Selfie file is too large (max 5 MB)");
      }
      const buffer = Buffer.concat(chunks);
      const imageSha256 = sha256Hex(buffer);

      const storageKey = `${request.auth.userId}_${Date.now()}.jpg`;
      try {
        await uploadVerificationSelfieObject(storageKey, buffer, "image/jpeg");
      } catch (error) {
        request.log.error({ err: error, userId: request.auth.userId }, "Supabase Storage upload failed");
        return sendError(reply, 502, "Failed to store selfie");
      }

      const objectUrlForWorker = selfieStorageUrl(storageKey);
      if (!objectUrlForWorker) {
        return sendError(reply, 503, "Storage is not configured");
      }

      await query(
        `UPDATE users
         SET verification_selfie_url = $2,
             face_embedding = NULL,
             is_verified = false,
             verification_failure_reason = NULL,
             verification_mismatched_photo_ids = '{}'
         WHERE id = $1`,
        [request.auth.userId, storageKey]
      );

      await enqueueSelfieEmbeddingJob(request.auth.userId, objectUrlForWorker, request.log);

      request.log.info(
        {
          userId: request.auth.userId,
          bytes: buffer.length,
          imageSha256
        },
        "Selfie stored — embedding job enqueued"
      );

      const signedUrl = await signedVerificationSelfieUrl(storageKey);
      return { ok: true, selfieUrl: signedUrl ?? objectUrlForWorker };
    }
  );

  app.delete("/users/me", { preHandler: authenticate }, async (request, reply) => {
    const deletion = await withTransaction<AccountDeletionRow | undefined>(async (client) => {
      const result = await client.query<AccountDeletionRow>(
        `
          UPDATE users
          SET is_active = false,
              deletion_requested_at = now(),
              deletion_scheduled_at = now() + interval '1 day'
          WHERE id = $1
            AND is_active = true
            AND deletion_scheduled_at IS NULL
          RETURNING phone_e164, deletion_scheduled_at
        `,
        [request.auth.userId]
      );

      const row = result.rows[0];
      if (!row) {
        return undefined;
      }

      await client.query(
        `
          UPDATE checkins
          SET checked_out_at = now()
          WHERE user_id = $1
            AND checked_out_at IS NULL
        `,
        [request.auth.userId]
      );
      await client.query("DELETE FROM device_tokens WHERE user_id = $1", [request.auth.userId]);
      await client.query("DELETE FROM otp_codes WHERE phone_e164 = $1", [row.phone_e164]);
      await client.query(
        `
          UPDATE refresh_tokens
          SET revoked_at = now()
          WHERE user_id = $1
            AND revoked_at IS NULL
        `,
        [request.auth.userId]
      );

      return row;
    });

    if (!deletion) {
      return sendError(reply, 404, "User not found");
    }

    return {
      ok: true,
      deletionScheduledAt: deletion.deletion_scheduled_at.toISOString()
    };
  });
}
