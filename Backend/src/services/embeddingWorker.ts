import type { FastifyInstance } from "fastify";
import type { FastifyBaseLogger } from "fastify";
import { query } from "../db/pool.js";
import { env } from "../config/env.js";
import {
  extractAllFaceEmbeddings,
  extractFaceEmbedding,
  FaceComparisonError,
  markSelfieVerificationRejected,
  verifyUserAgainstProfilePhotos
} from "./faceVerification.js";

type LoggerLike = Pick<FastifyBaseLogger, "info" | "warn" | "error">;

// Downloads from storage with auth headers if the URL is on our Supabase instance.
// Falls back to plain fetch for external/already-public URLs.
async function downloadPhoto(cdnUrl: string): Promise<Buffer> {
  const headers: Record<string, string> = {};
  if (env.supabase && cdnUrl.startsWith(env.supabase.url)) {
    headers["apikey"] = env.supabase.serviceRoleKey;
    headers["Authorization"] = `Bearer ${env.supabase.serviceRoleKey}`;
  }
  const response = await fetch(cdnUrl, { headers });
  if (!response.ok) {
    throw new Error(`Photo download failed: HTTP ${response.status} for ${cdnUrl}`);
  }
  return Buffer.from(await response.arrayBuffer());
}

// In-process job queue — stored in Postgres so jobs survive server restarts.
// A background worker polls every few seconds and processes pending jobs.

const POLL_INTERVAL_MS = 5_000;
const MAX_ATTEMPTS = 3;

type EmbeddingJobRow = {
  id: string;
  photo_id: string;
  cdn_url: string;
  attempts: number;
};

type SelfieEmbeddingJobRow = {
  id: string;
  user_id: string;
  cdn_url: string;
  attempts: number;
};

type PhotoUserRow = {
  user_id: string;
};

// Immediately extracts face embeddings for any of a user's photos that have
// face_embeddings = NULL (i.e. were uploaded before the worker ran or before
// this system was deployed). Called inline from the selfie endpoint so
// verification is not skipped on the first run.
export async function backfillUserPhotoEmbeddings(
  userId: string,
  logger?: LoggerLike
): Promise<void> {
  const result = await query<{ id: string; cdn_url: string }>(
    `SELECT id, cdn_url
     FROM profile_photos
     WHERE user_id = $1 AND face_embeddings IS NULL
     ORDER BY position`,
    [userId]
  );

  if (result.rows.length === 0) {
    logger?.info({ userId }, "Backfill: all photos already have embeddings");
    return;
  }

  logger?.info({ userId, count: result.rows.length }, "Backfill: starting embedding extraction for photos without embeddings");

  let succeeded = 0;
  let failed = 0;

  for (const photo of result.rows) {
    try {
      const buffer = await downloadPhoto(photo.cdn_url);
      const { embeddings, faceCount, detectorBackend } = await extractAllFaceEmbeddings(buffer, logger);
      const updateResult = await query(
        "UPDATE profile_photos SET face_embeddings = $2, face_count = $3 WHERE id = $1 AND cdn_url = $4",
        [photo.id, JSON.stringify(embeddings), faceCount, photo.cdn_url]
      );
      if (updateResult.rowCount === 0) {
        logger?.info({ photoId: photo.id }, "Backfill: skipped stale photo object");
        continue;
      }
      logger?.info({ photoId: photo.id, faceCount, detectorBackend }, "Backfill: embeddings stored");
      succeeded++;
    } catch (err) {
      logger?.warn({ err, photoId: photo.id }, "Backfill: failed for photo — skipping");
      failed++;
    }
  }

  logger?.info({ userId, total: result.rows.length, succeeded, failed }, "Backfill: completed");
}

export async function enqueueEmbeddingJob(photoId: string, cdnUrl: string, logger?: LoggerLike): Promise<void> {
  await query(
    `INSERT INTO embedding_jobs(photo_id, cdn_url)
     VALUES ($1, $2)
     ON CONFLICT (photo_id) DO UPDATE SET cdn_url = EXCLUDED.cdn_url, attempts = 0, failed_at = NULL, completed_at = NULL`,
    [photoId, cdnUrl]
  );
  logger?.info({ photoId }, "Embedding job: enqueued");
}

export async function enqueueSelfieEmbeddingJob(userId: string, cdnUrl: string, logger?: LoggerLike): Promise<void> {
  await query(
    `INSERT INTO selfie_embedding_jobs(user_id, cdn_url)
     VALUES ($1, $2)
     ON CONFLICT (user_id) DO UPDATE SET cdn_url = EXCLUDED.cdn_url, attempts = 0, failed_at = NULL, completed_at = NULL`,
    [userId, cdnUrl]
  );
  logger?.info({ userId }, "Selfie embedding job: enqueued");
}

async function processPendingSelfieJobs(logger: FastifyInstance["log"]): Promise<void> {
  const result = await query<SelfieEmbeddingJobRow>(
    `SELECT id, user_id, cdn_url, attempts
     FROM selfie_embedding_jobs
     WHERE completed_at IS NULL
       AND failed_at IS NULL
       AND attempts < $1
     ORDER BY created_at
     LIMIT 5`,
    [MAX_ATTEMPTS]
  );

  for (const job of result.rows) {
    try {
      await query("UPDATE selfie_embedding_jobs SET attempts = attempts + 1 WHERE id = $1", [job.id]);

      logger.info({ userId: job.user_id, attempt: job.attempts + 1 }, "Selfie embedding job: downloading selfie");

      const buffer = await downloadPhoto(job.cdn_url);

      logger.info({ userId: job.user_id }, "Selfie embedding job: extracting face embedding");
      const embedding = await extractFaceEmbedding(buffer, logger, { enforceLiveness: true });

      await query(
        "UPDATE users SET face_embedding = $2 WHERE id = $1",
        [job.user_id, JSON.stringify(embedding)]
      );

      logger.info({ userId: job.user_id }, "Selfie embedding job: embedding saved — starting backfill + verification");

      await backfillUserPhotoEmbeddings(job.user_id, logger);
      await verifyUserAgainstProfilePhotos(job.user_id, logger);

      await query("UPDATE selfie_embedding_jobs SET completed_at = now() WHERE id = $1", [job.id]);
    } catch (error) {
      const attempts = job.attempts + 1;
      logger.warn({ err: error, userId: job.user_id, attempts }, "Selfie embedding job: attempt failed");

      if (error instanceof FaceComparisonError && error.code === "spoof_detected") {
        await markSelfieVerificationRejected(job.user_id, "spoof_detected", logger);
        await query("UPDATE selfie_embedding_jobs SET failed_at = now() WHERE id = $1", [job.id]);
        logger.error(
          { userId: job.user_id, liveness: error.liveness, threshold: error.threshold },
          "Selfie embedding job: failed liveness check"
        );
        continue;
      }

      if (attempts >= MAX_ATTEMPTS) {
        await query("UPDATE selfie_embedding_jobs SET failed_at = now() WHERE id = $1", [job.id]);
        logger.error({ userId: job.user_id }, "Selfie embedding job: permanently failed after max attempts");
      }
    }
  }
}

async function processPendingJobs(logger: FastifyInstance["log"]): Promise<void> {
  const result = await query<EmbeddingJobRow>(
    `SELECT id, photo_id, cdn_url, attempts
     FROM embedding_jobs
     WHERE completed_at IS NULL
       AND failed_at IS NULL
       AND attempts < $1
     ORDER BY created_at
     LIMIT 5`,
    [MAX_ATTEMPTS]
  );

  for (const job of result.rows) {
    try {
      await query("UPDATE embedding_jobs SET attempts = attempts + 1 WHERE id = $1", [job.id]);

      logger.info({ photoId: job.photo_id, attempt: job.attempts + 1 }, "Embedding job: downloading photo");

      const buffer = await downloadPhoto(job.cdn_url);

      logger.info({ photoId: job.photo_id }, "Embedding job: extracting faces");
      const { embeddings, faceCount, detectorBackend } = await extractAllFaceEmbeddings(buffer, logger);

      const updateResult = await query(
        `UPDATE profile_photos
         SET face_embeddings = $2, face_count = $3
         WHERE id = $1 AND cdn_url = $4`,
        [job.photo_id, JSON.stringify(embeddings), faceCount, job.cdn_url]
      );

      if (updateResult.rowCount === 0) {
        await query("UPDATE embedding_jobs SET completed_at = now() WHERE id = $1 AND cdn_url = $2", [job.id, job.cdn_url]);
        logger.info({ photoId: job.photo_id }, "Embedding job: skipped stale photo object");
        continue;
      }

      await query("UPDATE embedding_jobs SET completed_at = now() WHERE id = $1 AND cdn_url = $2", [job.id, job.cdn_url]);

      logger.info({ photoId: job.photo_id, faceCount, detectorBackend }, "Embedding job: completed");

      // Re-run verification if this user has already submitted a selfie.
      // Covers: new photo added after verification, and newly-verified users
      // whose old photos were missing embeddings.
      const userRow = await query<PhotoUserRow>(
        "SELECT user_id FROM profile_photos WHERE id = $1 LIMIT 1",
        [job.photo_id]
      );
      const userId = userRow.rows[0]?.user_id;
      if (userId) {
        const hasSelfie = await query<{ face_embedding: number[] | null }>(
          "SELECT face_embedding FROM users WHERE id = $1 LIMIT 1",
          [userId]
        );
        if (Array.isArray(hasSelfie.rows[0]?.face_embedding) && hasSelfie.rows[0].face_embedding.length > 0) {
          logger.info({ userId, photoId: job.photo_id }, "Embedding job: triggering re-verification");
          verifyUserAgainstProfilePhotos(userId, logger).catch(err => {
            logger.warn({ err, userId }, "Re-verification after photo embedding failed");
          });
        }
      }
    } catch (error) {
      const attempts = job.attempts + 1;
      logger.warn({ err: error, photoId: job.photo_id, attempts }, "Embedding job: attempt failed");

      if (attempts >= MAX_ATTEMPTS) {
        await query("UPDATE embedding_jobs SET failed_at = now() WHERE id = $1", [job.id]);
        logger.error({ photoId: job.photo_id }, "Embedding job: permanently failed after max attempts");
      }
    }
  }
}

export function registerEmbeddingWorker(app: FastifyInstance): void {
  let isRunning = false;

  const run = async () => {
    if (isRunning) {
      app.log.info("Embedding worker: previous poll still running — skipping tick");
      return;
    }

    isRunning = true;
    try {
      try {
        await processPendingSelfieJobs(app.log);
      } catch (error) {
        app.log.error(error, "Embedding worker: selfie job poll error");
      }

      try {
        await processPendingJobs(app.log);
      } catch (error) {
        app.log.error(error, "Embedding worker: photo job poll error");
      }
    } finally {
      isRunning = false;
    }
  };

  const interval = setInterval(run, POLL_INTERVAL_MS);
  interval.unref();

  app.addHook("onClose", async () => {
    clearInterval(interval);
  });
}
