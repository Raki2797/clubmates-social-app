import { execFile, type ExecFileException } from "node:child_process";
import { access, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import type { FastifyBaseLogger } from "fastify";
import { env } from "../config/env.js";
import { query } from "../db/pool.js";
import { broadcastToUser } from "../realtime/chatHub.js";

const execFileAsync = promisify(execFile);

type UserVerificationRow = {
  verification_selfie_url: string | null;
  face_embedding: number[] | null;
};

type PhotoEmbeddingRow = {
  id: string;
  face_embeddings: number[][] | null;
  face_count: number | null;
};

export type FaceComparisonPayload = {
  same_person: boolean;
  confidence: number;
  distance: number;
  threshold: number;
  model: string;
  detector_backend: string;
  similarity_metric: string;
};

type LoggerLike = Pick<FastifyBaseLogger, "info" | "warn" | "error">;

type FaceLivenessPayload = {
  live_score: number;
  print_attack_score: number;
  replay_attack_score: number;
};

export class FaceComparisonError extends Error {
  constructor(
    message: string,
    public readonly code: "face_not_detected" | "image_processing_failed" | "spoof_detected",
    public readonly liveness?: FaceLivenessPayload,
    public readonly threshold?: number
  ) {
    super(message);
    this.name = "FaceComparisonError";
  }
}

type FaceComparisonConfig = {
  pythonBin: string;
  embeddingScriptPath: string;
  deepfaceHome: string;
  model: string;
  detector: string;
  distanceMetric: string;
  threshold: number;
  antiSpoofModelPath: string;
  antiSpoofThreshold: number;
  timeoutMs: number;
};

export type FaceVerificationResult =
  | {
      status: "verified";
      isVerified: true;
      mismatchedPhotoIds: [];
      verificationFailureReason: null;
    }
  | {
      status: "rejected";
      isVerified: false;
      // Photo IDs whose faces didn't match the selfie
      mismatchedPhotoIds: string[];
      verificationFailureReason: "photo_mismatch";
    }
  | {
      status: "skipped";
      isVerified: false;
      mismatchedPhotoIds: string[];
      verificationFailureReason: "no_selfie" | "no_face_in_any_photo" | "spoof_detected";
    }
  | {
      status: "error";
      isVerified: false;
      mismatchedPhotoIds: [];
      verificationFailureReason: null;
    };

async function fileExists(filePath: string): Promise<boolean> {
  try {
    await access(filePath);
    return true;
  } catch {
    return false;
  }
}

async function comparisonConfig(): Promise<FaceComparisonConfig> {
  const configured = env.faceVerification;
  if (configured) {
    return configured;
  }

  const backendRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
  const localPython = path.join(backendRoot, ".venv-face", "bin", "python");
  const pythonBin = (await fileExists(localPython)) ? localPython : "python3";

  return {
    pythonBin,
    embeddingScriptPath: path.join(backendRoot, "scripts", "extract_embedding.py"),
    deepfaceHome: path.join(backendRoot, ".deepface-home"),
    model: "ArcFace",
    detector: "scrfd",
    distanceMetric: "cosine",
    threshold: 0.70,
    antiSpoofModelPath: path.join(backendRoot, "models", "minifasnet_v2.onnx"),
    antiSpoofThreshold: 0.50,
    timeoutMs: 120_000
  };
}

const DEFAULT_FACE_COSINE_THRESHOLD = 0.70;
const DEFAULT_FACE_EMBEDDING_DIMS = 512;

function isUsableEmbedding(value: number[]): boolean {
  return value.length > 0 && value.every(Number.isFinite);
}

function cosineDistance(a: number[], b: number[]): number | null {
  if (a.length !== b.length || !isUsableEmbedding(a) || !isUsableEmbedding(b)) {
    return null;
  }

  let dot = 0, normA = 0, normB = 0;
  for (let i = 0; i < a.length; i++) {
    dot   += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA === 0 || normB === 0) return null;
  return 1 - dot / (Math.sqrt(normA) * Math.sqrt(normB));
}

type EmbeddingsPayload = {
  embeddings: number[][];
  count: number;
  model: string;
  detector_backend: string;
  liveness?: FaceLivenessPayload;
};

function broadcastVerificationUpdate(userId: string, result: FaceVerificationResult): void {
  broadcastToUser(userId, {
    type: "profile.verification.updated",
    isVerified: result.isVerified,
    verificationFailureReason: result.verificationFailureReason,
    verificationMismatchedPhotoIds: result.mismatchedPhotoIds
  });
}

const fallbackEmbeddingDetectors: string[] = [];

function embeddingDetectors(primaryDetector: string): string[] {
  return [
    primaryDetector,
    ...fallbackEmbeddingDetectors.filter(detector => detector !== primaryDetector)
  ];
}

async function executeEmbeddingScript(
  imagePath: string,
  detector: string,
  config: FaceComparisonConfig,
  extraArgs: string[]
): Promise<string> {
  const { stdout } = await execFileAsync(
    config.pythonBin,
    [config.embeddingScriptPath, imagePath, "--detector", detector, ...extraArgs],
    {
      env: {
        ...process.env,
        DEEPFACE_HOME: config.deepfaceHome,
        INSIGHTFACE_HOME: config.deepfaceHome,
        FACE_VERIFICATION_MODEL_HOME: config.deepfaceHome
      },
      timeout: config.timeoutMs,
      maxBuffer: 10 * 1024 * 1024
    }
  );
  return stdout;
}

async function runEmbeddingScript(
  imageBuffer: Buffer,
  config: FaceComparisonConfig,
  extraArgs: string[],
  logger?: LoggerLike
): Promise<EmbeddingsPayload> {
  await mkdir(config.deepfaceHome, { recursive: true });

  const tempDir = await mkdtemp(path.join(tmpdir(), "clubmates-emb-"));
  const imagePath = path.join(tempDir, "image.jpg");

  try {
    await writeFile(imagePath, imageBuffer);

    let stdout: string | undefined;
    let lastFaceError: FaceComparisonError | undefined;
    for (const detector of embeddingDetectors(config.detector)) {
      try {
        stdout = await executeEmbeddingScript(imagePath, detector, config, extraArgs);
        if (detector !== config.detector) {
          logger?.info({ detector }, "Face embedding detected with fallback detector");
        }
        break;
      } catch (error) {
        const execError = error as ExecFileException & { stderr?: string };
        const faceError = parsePythonFaceError(execError.stderr);
        if (faceError.code !== "face_not_detected") {
          throw faceError;
        }
        lastFaceError = faceError;
        logger?.warn({ detector }, "Face embedding detector could not find a face");
      }
    }

    if (!stdout) {
      throw lastFaceError ?? new FaceComparisonError(
        "Face could not be detected in the image. Please use a clear human face photo.",
        "face_not_detected"
      );
    }

    const line = stdout.split(/\r?\n/).map(l => l.trim()).filter(Boolean).at(-1);
    if (!line) throw new Error("Embedding script produced no output");

    const parsed = JSON.parse(line) as EmbeddingsPayload;
    if (!Array.isArray(parsed.embeddings) || parsed.embeddings.length === 0) {
      throw new Error("Embedding script output was invalid");
    }

    logger?.info(
      {
        count: parsed.count,
        model: parsed.model,
        detectorBackend: parsed.detector_backend
      },
      "Face embeddings extracted"
    );
    return parsed;
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
}

type ExtractFaceEmbeddingOptions = {
  enforceLiveness?: boolean;
};

// Extracts the single most prominent face embedding. Used for selfies where
// exactly one face is expected. Throws FaceComparisonError if none found.
export async function extractFaceEmbedding(
  imageBuffer: Buffer,
  logger?: LoggerLike,
  options: ExtractFaceEmbeddingOptions = {}
): Promise<number[]> {
  logger?.info({ bytes: imageBuffer.length }, "Extracting selfie face embedding (first-only)");
  const config = await comparisonConfig();
  const args = ["--first-only"];
  if (options.enforceLiveness) {
    args.push(
      "--anti-spoof",
      "--anti-spoof-model",
      config.antiSpoofModelPath,
      "--anti-spoof-threshold",
      String(config.antiSpoofThreshold)
    );
  }
  const result = await runEmbeddingScript(imageBuffer, config, args, logger);
  logger?.info(
    {
      dims: result.embeddings[0].length,
      model: result.model,
      detectorBackend: result.detector_backend,
      liveness: result.liveness
    },
    "Selfie embedding extracted"
  );
  return result.embeddings[0];
}

// Extracts embeddings for every face in the image. Returns an empty array if
// no faces are detected (does not throw). Used for profile photos which may
// contain multiple people.
export async function extractAllFaceEmbeddings(
  imageBuffer: Buffer,
  logger?: LoggerLike
): Promise<{ embeddings: number[][]; faceCount: number; detectorBackend: string | null }> {
  logger?.info({ bytes: imageBuffer.length }, "Extracting all face embeddings from photo");
  const config = await comparisonConfig();
  try {
    const result = await runEmbeddingScript(imageBuffer, config, [], logger);
    logger?.info(
      {
        faceCount: result.count,
        dims: result.embeddings[0]?.length,
        model: result.model,
        detectorBackend: result.detector_backend
      },
      "Photo face embeddings extracted"
    );
    return {
      embeddings: result.embeddings,
      faceCount: result.count,
      detectorBackend: result.detector_backend
    };
  } catch (error) {
    if (error instanceof FaceComparisonError && error.code === "face_not_detected") {
      logger?.info({ bytes: imageBuffer.length }, "No face detected in photo — storing empty embeddings");
      return { embeddings: [], faceCount: 0, detectorBackend: null };
    }
    throw error;
  }
}

// Returns the lowest cosine distance between the selfie embedding and any
// candidate embedding across all profile photos. Returns null if the
// candidate list is empty.
export function bestMatchAcrossEmbeddings(
  selfieEmbedding: number[],
  candidates: number[][]
): {
  distance: number | null;
  threshold: number;
  matched: boolean;
  reason: "matched" | "photo_mismatch" | "embedding_dimension_mismatch";
  selfieDims: number;
  candidateDims: number[];
} | null {
  if (candidates.length === 0) return null;

  let best: number | null = null;
  const candidateDims = candidates.map(candidate => candidate.length);
  for (const candidate of candidates) {
    const d = cosineDistance(selfieEmbedding, candidate);
    if (d === null) continue;
    if (best === null || d < best) best = d;
  }

  const threshold = env.faceVerification?.threshold ?? DEFAULT_FACE_COSINE_THRESHOLD;
  const matched = best !== null && best < threshold;
  return {
    distance: best,
    threshold,
    matched,
    reason: best === null ? "embedding_dimension_mismatch" : matched ? "matched" : "photo_mismatch",
    selfieDims: selfieEmbedding.length,
    candidateDims
  };
}

export function compareEmbeddingToEmbedding(
  storedEmbedding: number[],
  newEmbedding: number[]
): FaceComparisonPayload {
  const distance = cosineDistance(storedEmbedding, newEmbedding) ?? 1;
  const threshold = env.faceVerification?.threshold ?? DEFAULT_FACE_COSINE_THRESHOLD;
  const confidence = Math.round(Math.max(0, Math.min(100, (1 - distance / threshold) * 100)) * 100) / 100;

  return {
    same_person: distance < threshold,
    confidence,
    distance,
    threshold,
    model: env.faceVerification?.model ?? "ArcFace",
    detector_backend: env.faceVerification?.detector ?? "scrfd",
    similarity_metric: "cosine"
  };
}

export async function markUserUnverified(userId: string): Promise<void> {
  await query(
    `
      UPDATE users
      SET is_verified = false,
          verification_failure_reason = NULL,
          verification_mismatched_photo_ids = '{}'
      WHERE id = $1
    `,
    [userId]
  );
}

export async function markSelfieVerificationRejected(
  userId: string,
  reason: "spoof_detected" | "no_selfie",
  logger?: LoggerLike
): Promise<void> {
  await query(
    `
      UPDATE users
      SET is_verified = false,
          verification_failure_reason = $2,
          verification_mismatched_photo_ids = '{}'
      WHERE id = $1
    `,
    [userId, reason]
  );
  const result: FaceVerificationResult = {
    status: "skipped",
    isVerified: false,
    mismatchedPhotoIds: [],
    verificationFailureReason: reason
  };
  logger?.warn({ userId, reason }, "Face verification: selfie rejected");
  broadcastVerificationUpdate(userId, result);
}

function parsePythonFaceError(stderr?: string): FaceComparisonError {
  const fallback = new FaceComparisonError(
    "Face comparison failed while processing the uploaded images",
    "image_processing_failed"
  );

  const line = stderr
    ?.split(/\r?\n/)
    .map((entry) => entry.trim())
    .filter(Boolean)
    .at(-1);

  if (!line) {
    return fallback;
  }

  try {
    const parsed = JSON.parse(line) as {
      error?: string;
      code?: string;
      liveness?: FaceLivenessPayload;
      threshold?: number;
    };
    const message = parsed.error || fallback.message;
    if (parsed.code === "spoof_detected") {
      return new FaceComparisonError(message, "spoof_detected", parsed.liveness, parsed.threshold);
    }
    if (parsed.code === "face_not_detected") {
      return new FaceComparisonError(message, "face_not_detected");
    }
    const lowerMessage = message.toLowerCase();
    return new FaceComparisonError(
      message,
      lowerMessage.includes("face could not be detected") ||
        lowerMessage.includes("processing img")
        ? "face_not_detected"
        : "image_processing_failed"
    );
  } catch {
    return fallback;
  }
}

// Verifies that:
//   1. Every processed profile photo contains at least one detectable face.
//   2. The selfie matches at least one face in each profile photo.
//   3. All photos with detectable faces belong to the same person as the selfie.
//
// A photo passes if its best cosine distance to the selfie is below the threshold.
// Verification is rejected if ANY profile photo has no face or fails to match the selfie.
export async function verifyUserAgainstProfilePhotos(
  userId: string,
  logger?: LoggerLike
): Promise<FaceVerificationResult> {
  logger?.info({ userId }, "Face verification: starting");

  const userResult = await query<UserVerificationRow>(
    "SELECT verification_selfie_url, face_embedding FROM users WHERE id = $1 LIMIT 1",
    [userId]
  );

  const userRow = userResult.rows[0];
  if (!userRow?.verification_selfie_url?.trim()) {
    logger?.warn({ userId }, "Face verification: skipped — no selfie on record");
    await query(
      "UPDATE users SET is_verified = false, verification_failure_reason = $2, verification_mismatched_photo_ids = '{}' WHERE id = $1",
      [userId, "no_selfie"]
    );
    const result: FaceVerificationResult = {
      status: "skipped",
      isVerified: false,
      mismatchedPhotoIds: [],
      verificationFailureReason: "no_selfie"
    };
    broadcastVerificationUpdate(userId, result);
    return result;
  }

  if (!Array.isArray(userRow.face_embedding) || userRow.face_embedding.length === 0) {
    logger?.warn({ userId }, "Face verification: skipped — selfie has no stored embedding");
    await query(
      "UPDATE users SET is_verified = false, verification_failure_reason = $2, verification_mismatched_photo_ids = '{}' WHERE id = $1",
      [userId, "no_selfie"]
    );
    const result: FaceVerificationResult = {
      status: "skipped",
      isVerified: false,
      mismatchedPhotoIds: [],
      verificationFailureReason: "no_selfie"
    };
    broadcastVerificationUpdate(userId, result);
    return result;
  }

  if (userRow.face_embedding.length !== DEFAULT_FACE_EMBEDDING_DIMS) {
    logger?.warn(
      { userId, selfieDims: userRow.face_embedding.length, expectedDims: DEFAULT_FACE_EMBEDDING_DIMS },
      "Face verification: skipped — selfie embedding was generated by an incompatible model"
    );
    await query(
      `UPDATE users
       SET face_embedding = NULL,
           is_verified = false,
           verification_failure_reason = $2,
           verification_mismatched_photo_ids = '{}'
       WHERE id = $1`,
      [userId, "no_selfie"]
    );
    const result: FaceVerificationResult = {
      status: "skipped",
      isVerified: false,
      mismatchedPhotoIds: [],
      verificationFailureReason: "no_selfie"
    };
    broadcastVerificationUpdate(userId, result);
    return result;
  }

  const photosResult = await query<PhotoEmbeddingRow>(
    "SELECT id, face_embeddings, face_count FROM profile_photos WHERE user_id = $1 AND face_embeddings IS NOT NULL",
    [userId]
  );

  const photosWithoutFaces = photosResult.rows.filter(
    r => Array.isArray(r.face_embeddings) && r.face_embeddings.length === 0
  );

  const photosWithFaces = photosResult.rows.filter(
    r => Array.isArray(r.face_embeddings) && r.face_embeddings.length > 0
  );

  logger?.info(
    {
      userId,
      totalPhotos: photosResult.rows.length,
      photosWithFaces: photosWithFaces.length,
      photosWithoutFaces: photosWithoutFaces.length
    },
    "Face verification: loaded profile photo embeddings"
  );

  if (photosWithFaces.length === 0) {
    const noFacePhotoIds = photosWithoutFaces.map(photo => photo.id);
    logger?.warn(
      { userId, totalPhotos: photosResult.rows.length, noFacePhotoIds },
      "Face verification: skipped — no photos have detectable faces"
    );
    await query(
      "UPDATE users SET is_verified = false, verification_failure_reason = $2, verification_mismatched_photo_ids = $3 WHERE id = $1",
      [userId, "no_face_in_any_photo", noFacePhotoIds]
    );
    const result: FaceVerificationResult = {
      status: "skipped",
      isVerified: false,
      mismatchedPhotoIds: noFacePhotoIds,
      verificationFailureReason: "no_face_in_any_photo"
    };
    broadcastVerificationUpdate(userId, result);
    return result;
  }

  try {
    const selfieEmbedding = userRow.face_embedding;
    const mismatchedPhotoIds = photosWithoutFaces.map(photo => photo.id);

    for (const photo of photosWithoutFaces) {
      logger?.warn(
        { userId, photoId: photo.id, faceCount: photo.face_count },
        "Face verification: photo rejected — no detectable face"
      );
    }

    // Check every photo individually — all must contain the selfie person
    for (const photo of photosWithFaces) {
      const best = bestMatchAcrossEmbeddings(selfieEmbedding, photo.face_embeddings!);
      const passed = best?.matched ?? false;
      logger?.info(
        {
          userId,
          photoId: photo.id,
          faceCount: photo.face_count,
          bestDistance: best?.distance === null || best === null ? null : Number(best.distance.toFixed(4)),
          threshold: best?.threshold ?? (env.faceVerification?.threshold ?? DEFAULT_FACE_COSINE_THRESHOLD),
          reason: best?.reason ?? "no_face_embeddings",
          selfieDims: best?.selfieDims ?? selfieEmbedding.length,
          candidateDims: best?.candidateDims ?? [],
          passed
        },
        passed ? "Face verification: photo passed" : "Face verification: photo mismatch"
      );
      if (!passed) {
        mismatchedPhotoIds.push(photo.id);
      }
    }

    const isVerified = mismatchedPhotoIds.length === 0;
    const failureReason = isVerified ? null : "photo_mismatch";
    const faceMismatchCount = mismatchedPhotoIds.length - photosWithoutFaces.length;
    const passedFacePhotoCount = photosWithFaces.length - faceMismatchCount;

    await query(
      `UPDATE users
       SET is_verified = $2,
           verification_failure_reason = $3,
           verification_mismatched_photo_ids = $4
       WHERE id = $1`,
      [userId, isVerified, failureReason, mismatchedPhotoIds]
    );

    logger?.info(
      {
        userId,
        isVerified,
        totalChecked: photosWithFaces.length,
        passed: passedFacePhotoCount,
        failed: mismatchedPhotoIds.length,
        mismatchedPhotoIds
      },
      isVerified ? "Face verification: verified ✓" : "Face verification: rejected — photo mismatch"
    );

    if (isVerified) {
      const result: FaceVerificationResult = {
        status: "verified",
        isVerified: true,
        mismatchedPhotoIds: [],
        verificationFailureReason: null
      };
      broadcastVerificationUpdate(userId, result);
      return result;
    }

    const result: FaceVerificationResult = {
      status: "rejected",
      isVerified: false,
      mismatchedPhotoIds,
      verificationFailureReason: "photo_mismatch"
    };
    broadcastVerificationUpdate(userId, result);
    return result;
  } catch (error) {
    logger?.error({ err: error, userId }, "Face verification: unexpected error");
    return { status: "error", isVerified: false, mismatchedPhotoIds: [], verificationFailureReason: null };
  }
}
