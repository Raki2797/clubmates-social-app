import { beforeEach, vi } from "vitest";
import { signAccessToken } from "../../src/utils/auth.js";

const { queryMock, withTransactionMock } = vi.hoisted(() => ({
  queryMock: vi.fn(),
  withTransactionMock: vi.fn()
}));

const {
  uploadProfilePhotoObjectMock,
  uploadVerificationSelfieObjectMock,
  downloadProfilePhotoObjectMock,
  signedProfilePhotoUrlMock,
  signedVerificationSelfieUrlMock,
  deleteProfilePhotoObjectsMock,
  withSignedPhotoUrlsMock,
  authenticatedPhotoUrlMock,
  authenticatedVerificationSelfieUrlMock
} = vi.hoisted(() => ({
  uploadProfilePhotoObjectMock: vi.fn(),
  uploadVerificationSelfieObjectMock: vi.fn(),
  downloadProfilePhotoObjectMock: vi.fn(),
  signedProfilePhotoUrlMock: vi.fn(),
  signedVerificationSelfieUrlMock: vi.fn(),
  deleteProfilePhotoObjectsMock: vi.fn(),
  withSignedPhotoUrlsMock: vi.fn(async (photos: unknown[]) => photos),
  authenticatedPhotoUrlMock: vi.fn((key: string) => `https://supabase.example.com/storage/v1/object/profile-photos/${key}`),
  authenticatedVerificationSelfieUrlMock: vi.fn((key: string) => `https://supabase.example.com/storage/v1/object/verification-selfies/${key}`)
}));

const {
  verifyUploadedProfilePhotoMock,
  reevaluateUserFaceVerificationMock,
  extractFaceEmbeddingMock,
  verifyUserAgainstProfilePhotosMock
} = vi.hoisted(() => ({
  verifyUploadedProfilePhotoMock: vi.fn(),
  reevaluateUserFaceVerificationMock: vi.fn(),
  extractFaceEmbeddingMock: vi.fn(),
  verifyUserAgainstProfilePhotosMock: vi.fn()
}));

const { enqueueSelfieEmbeddingJobMock } = vi.hoisted(() => ({
  enqueueSelfieEmbeddingJobMock: vi.fn().mockResolvedValue(undefined)
}));

const { fetchMock } = vi.hoisted(() => ({
  fetchMock: vi.fn()
}));

vi.mock("../../src/db/pool.js", () => ({
  query: queryMock,
  withTransaction: withTransactionMock,
  closePool: vi.fn()
}));

vi.mock("../../src/services/profilePhotoStorage.js", () => ({
  uploadProfilePhotoObject: uploadProfilePhotoObjectMock,
  uploadVerificationSelfieObject: uploadVerificationSelfieObjectMock,
  downloadProfilePhotoObject: downloadProfilePhotoObjectMock,
  signedProfilePhotoUrl: signedProfilePhotoUrlMock,
  signedVerificationSelfieUrl: signedVerificationSelfieUrlMock,
  deleteProfilePhotoObjects: deleteProfilePhotoObjectsMock,
  withSignedPhotoUrls: withSignedPhotoUrlsMock,
  authenticatedPhotoUrl: authenticatedPhotoUrlMock,
  authenticatedVerificationSelfieUrl: authenticatedVerificationSelfieUrlMock
}));

vi.mock("../../src/services/faceVerification.js", () => ({
  verifyUploadedProfilePhoto: verifyUploadedProfilePhotoMock,
  reevaluateUserFaceVerification: reevaluateUserFaceVerificationMock,
  verifyUserAgainstProfilePhotos: verifyUserAgainstProfilePhotosMock,
  extractFaceEmbedding: extractFaceEmbeddingMock,
  compareEmbeddingToEmbedding: (storedEmbedding: number[], newEmbedding: number[]) => {
    let dot = 0;
    let normA = 0;
    let normB = 0;
    for (let index = 0; index < storedEmbedding.length; index += 1) {
      dot += storedEmbedding[index] * newEmbedding[index];
      normA += storedEmbedding[index] * storedEmbedding[index];
      normB += newEmbedding[index] * newEmbedding[index];
    }
    const distance = normA === 0 || normB === 0
      ? 1
      : 1 - dot / (Math.sqrt(normA) * Math.sqrt(normB));
    const threshold = 0.70;
    return {
      same_person: distance < threshold,
      confidence: Math.round(Math.max(0, Math.min(100, (1 - distance / threshold) * 100)) * 100) / 100,
      distance,
      threshold,
      model: "ArcFace",
      detector_backend: "scrfd",
      similarity_metric: "cosine"
    };
  },
  FaceComparisonError: class FaceComparisonError extends Error {
    constructor(
      message: string,
      public readonly code: "face_not_detected" | "image_processing_failed" | "spoof_detected"
    ) {
      super(message);
      this.name = "FaceComparisonError";
    }
  }
}));

const { enqueueEmbeddingJobMock, backfillUserPhotoEmbeddingsMock } = vi.hoisted(() => ({
  enqueueEmbeddingJobMock: vi.fn().mockResolvedValue(undefined),
  backfillUserPhotoEmbeddingsMock: vi.fn().mockResolvedValue(undefined)
}));

vi.mock("../../src/services/embeddingWorker.js", () => ({
  enqueueEmbeddingJob: enqueueEmbeddingJobMock,
  enqueueSelfieEmbeddingJob: enqueueSelfieEmbeddingJobMock,
  backfillUserPhotoEmbeddings: backfillUserPhotoEmbeddingsMock,
  registerEmbeddingWorker: vi.fn()
}));

vi.mock("../../src/config/env.js", () => ({
  env: {
    nodeEnv: "test",
    host: "0.0.0.0",
    port: 3000,
    databaseUrl: "postgresql://postgres:postgres@localhost:5432/clubmates_test",
    databaseSsl: false,
    jwtSecret: "test-secret",
    accessTokenTtlSeconds: 900,
    refreshTokenDays: 30,
    devOtpCode: "123456",
    corsOrigin: ["*"],
      supabase: {
        url: "https://supabase.example.com",
        serviceRoleKey: "service-role-key",
        profilePhotosBucket: "profile-photos",
        verificationSelfiesBucket: "verification-selfies",
        signedUrlTtlSeconds: 3600
      },
    supabaseUrl: "https://supabase.example.com",
    supabaseServiceRoleKey: "service-role-key",
    faceVerification: {
      pythonBin: "python3",
      embeddingScriptPath: "/app/scripts/extract_embedding.py",
      deepfaceHome: "/app/.deepface-home",
      model: "ArcFace",
      detector: "scrfd",
      distanceMetric: "cosine",
      threshold: 0.70,
      antiSpoofModelPath: "/app/models/minifasnet_v2.onnx",
      antiSpoofThreshold: 0.50,
      timeoutMs: 120000
    }
  }
}));

import { buildApp } from "../../src/app.js";

function authHeader(userId: string): Record<string, string> {
  const token = signAccessToken({ userId, phone: "+911234567890" });
  return { authorization: `Bearer ${token}` };
}

function multipartPayload(fieldName: string, filename: string, contentType: string, body: Buffer) {
  const boundary = "----clubmates-test-boundary";
  const header = Buffer.from(
    `--${boundary}\r\nContent-Disposition: form-data; name="${fieldName}"; filename="${filename}"\r\nContent-Type: ${contentType}\r\n\r\n`
  );
  const footer = Buffer.from(`\r\n--${boundary}--\r\n`);

  return {
    boundary,
    payload: Buffer.concat([header, body, footer])
  };
}

const me = "505f7fc3-2d06-4b96-aa90-6380f511ffde";

describe("user verification routes", () => {
  beforeEach(() => {
    queryMock.mockReset();
    withTransactionMock.mockReset();
    uploadProfilePhotoObjectMock.mockReset();
    uploadVerificationSelfieObjectMock.mockReset();
    downloadProfilePhotoObjectMock.mockReset();
    signedProfilePhotoUrlMock.mockReset();
    signedVerificationSelfieUrlMock.mockReset();
    authenticatedPhotoUrlMock.mockClear();
    authenticatedVerificationSelfieUrlMock.mockClear();
    deleteProfilePhotoObjectsMock.mockReset();
    withSignedPhotoUrlsMock.mockClear();
    reevaluateUserFaceVerificationMock.mockReset();
    verifyUserAgainstProfilePhotosMock.mockReset().mockResolvedValue({
      status: "verified",
      isVerified: true,
      mismatchedPhotoIds: [],
      verificationFailureReason: null
    });
    verifyUploadedProfilePhotoMock.mockReset();
    extractFaceEmbeddingMock.mockReset();
    enqueueEmbeddingJobMock.mockReset().mockResolvedValue(undefined);
    enqueueSelfieEmbeddingJobMock.mockReset().mockResolvedValue(undefined);
    backfillUserPhotoEmbeddingsMock.mockReset().mockResolvedValue(undefined);
    fetchMock.mockReset();

    vi.stubGlobal("fetch", fetchMock);

    signedProfilePhotoUrlMock.mockResolvedValue("https://cdn.example.com/photo.jpg");
    signedVerificationSelfieUrlMock.mockResolvedValue("https://cdn.example.com/selfie.jpg");
    withTransactionMock.mockImplementation(async (cb: (client: { query: typeof queryMock }) => Promise<unknown>) => {
      return await cb({ query: queryMock });
    });
  });

  it("compares the uploaded main photo with the earlier verification selfie", async () => {
    const clientPhotoId = "11111111-1111-4111-8111-111111111111";
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM profile_photos") && sql.includes("WHERE user_id = $1 AND position = $2")) {
        return { rows: [], rowCount: 0 };
      }
      if (sql.includes("INSERT INTO profile_photos")) {
        return {
          rows: [{
            id: clientPhotoId,
            storage_key: `${me}/${clientPhotoId}.jpg`,
            cdn_url: `https://supabase.example.com/storage/v1/object/profile-photos/${me}/${clientPhotoId}.jpg`,
            position: 0
          }],
          rowCount: 1
        };
      }
      return { rows: [], rowCount: 0 };
    });

    const { boundary, payload } = multipartPayload(
      "photo",
      "profile.jpg",
      "image/jpeg",
      Buffer.from("fake-jpeg-binary")
    );

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: `/users/me/photos?position=0&clientPhotoId=${clientPhotoId}`,
      headers: {
        ...authHeader(me),
        "content-type": `multipart/form-data; boundary=${boundary}`
      },
      payload
    });

    expect(response.statusCode).toBe(200);
    expect(uploadProfilePhotoObjectMock).toHaveBeenCalledWith(
      `${me}/${clientPhotoId}.jpg`,
      expect.any(Buffer),
      "image/jpeg"
    );
    expect(enqueueEmbeddingJobMock).toHaveBeenCalledWith(
      clientPhotoId,
      `https://supabase.example.com/storage/v1/object/profile-photos/${me}/${clientPhotoId}.jpg`,
      expect.any(Object)
    );
    expect(verifyUploadedProfilePhotoMock).not.toHaveBeenCalled();
    expect(signedProfilePhotoUrlMock).not.toHaveBeenCalled();
    expect(response.json()).toEqual({
      photo: {
        id: clientPhotoId,
        storageKey: `${me}/${clientPhotoId}.jpg`,
        cdnUrl: `https://supabase.example.com/storage/v1/object/profile-photos/${me}/${clientPhotoId}.jpg`,
        position: 0
      }
    });
    await app.close();
  });

  it("rejects an invalid client photo id before uploading", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const { boundary, payload } = multipartPayload(
      "photo",
      "profile.jpg",
      "image/jpeg",
      Buffer.from("fake-jpeg-binary")
    );

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/users/me/photos?position=0&clientPhotoId=not-a-uuid",
      headers: {
        ...authHeader(me),
        "content-type": `multipart/form-data; boundary=${boundary}`
      },
      payload
    });

    expect(response.statusCode).toBe(400);
    expect(response.json()).toEqual({ error: "clientPhotoId must be a valid UUID" });
    expect(uploadProfilePhotoObjectMock).not.toHaveBeenCalled();
    await app.close();
  });

  it("accepts Postman uploads that use octet-stream with a jpg filename", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM profile_photos") && sql.includes("WHERE user_id = $1 AND position = $2")) {
        return { rows: [], rowCount: 0 };
      }
      if (sql.includes("INSERT INTO profile_photos")) {
        return {
          rows: [{
            id: "22222222-2222-4222-8222-222222222222",
            storage_key: `${me}/22222222-2222-4222-8222-222222222222.jpg`,
            cdn_url: "https://cdn.example.com/postman-photo.jpg",
            position: 1
          }],
          rowCount: 1
        };
      }
      return { rows: [], rowCount: 0 };
    });

    const { boundary, payload } = multipartPayload(
      "photo",
      "profile-test.jpg",
      "application/octet-stream",
      Buffer.from("postman-jpeg-binary")
    );

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/users/me/photos?position=1",
      headers: {
        ...authHeader(me),
        "content-type": `multipart/form-data; boundary=${boundary}`
      },
      payload
    });

    expect(response.statusCode).toBe(200);
    expect(uploadProfilePhotoObjectMock).toHaveBeenCalledWith(
      expect.stringContaining(".jpg"),
      expect.any(Buffer),
      "application/octet-stream"
    );
    await app.close();
  });

  it("does not trigger face comparison for non-primary profile photos", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM profile_photos") && sql.includes("WHERE user_id = $1 AND position = $2")) {
        return { rows: [], rowCount: 0 };
      }
      if (sql.includes("INSERT INTO profile_photos")) {
        return {
          rows: [{
            id: "photo-2",
            storage_key: `${me}/photo-2.jpg`,
            cdn_url: "https://cdn.example.com/photo-2.jpg",
            position: 1
          }],
          rowCount: 1
        };
      }
      return { rows: [], rowCount: 0 };
    });

    const { boundary, payload } = multipartPayload(
      "photo",
      "side.jpg",
      "image/jpeg",
      Buffer.from("fake-side-image")
    );

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/users/me/photos?position=1",
      headers: {
        ...authHeader(me),
        "content-type": `multipart/form-data; boundary=${boundary}`
      },
      payload
    });

    expect(response.statusCode).toBe(200);
    expect(verifyUploadedProfilePhotoMock).not.toHaveBeenCalled();
    expect(response.json()).toEqual({
      photo: {
        id: "photo-2",
        storageKey: `${me}/photo-2.jpg`,
        cdnUrl: "https://cdn.example.com/photo-2.jpg",
        position: 1
      }
    });
    await app.close();
  });

  it("deletes the replaced profile photo object from storage", async () => {
    const oldStorageKey = `${me}/old-photo.jpg`;
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM profile_photos") && sql.includes("WHERE user_id = $1 AND position = $2")) {
        return {
          rows: [{
            id: "photo-1",
            storage_key: oldStorageKey,
            cdn_url: "https://cdn.example.com/old-photo.jpg",
            position: 0
          }],
          rowCount: 1
        };
      }
      if (sql.includes("INSERT INTO profile_photos")) {
        return {
          rows: [{
            id: "photo-1",
            storage_key: `${me}/new-photo.jpg`,
            cdn_url: "https://cdn.example.com/new-photo.jpg",
            position: 0
          }],
          rowCount: 1
        };
      }
      return { rows: [], rowCount: 0 };
    });

    const { boundary, payload } = multipartPayload(
      "photo",
      "profile.jpg",
      "image/jpeg",
      Buffer.from("replacement-jpeg-binary")
    );

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/users/me/photos?position=0",
      headers: {
        ...authHeader(me),
        "content-type": `multipart/form-data; boundary=${boundary}`
      },
      payload
    });

    expect(response.statusCode).toBe(200);
    expect(deleteProfilePhotoObjectsMock).toHaveBeenCalledWith([oldStorageKey]);
    await app.close();
  });

  it("deletes the profile photo object from storage when a photo is removed", async () => {
    const storageKey = `${me}/photo-to-delete.jpg`;
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("DELETE FROM profile_photos")) {
        return {
          rows: [{
            id: "photo-delete",
            storage_key: storageKey,
            cdn_url: "https://cdn.example.com/photo-to-delete.jpg",
            position: 1
          }],
          rowCount: 1
        };
      }
      if (sql.includes("SELECT face_embedding FROM users")) {
        return { rows: [{ face_embedding: [1, 0, 0] }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "DELETE",
      url: "/users/me/photos/photo-delete",
      headers: authHeader(me)
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ ok: true });
    expect(deleteProfilePhotoObjectsMock).toHaveBeenCalledWith([storageKey]);
    expect(verifyUserAgainstProfilePhotosMock).toHaveBeenCalledWith(me, expect.anything());
    await app.close();
  });

  it("stores the verification selfie without comparing immediately", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("UPDATE users") && sql.includes("verification_selfie_url = $2")) {
        return { rows: [], rowCount: 1 };
      }
      if (sql.includes("FROM profile_photos") && sql.includes("position = 0")) {
        return { rows: [], rowCount: 0 };
      }
      return { rows: [], rowCount: 0 };
    });
    uploadVerificationSelfieObjectMock.mockResolvedValue(undefined);

    const { boundary, payload } = multipartPayload(
      "selfie",
      "selfie.jpg",
      "image/jpeg",
      Buffer.from("fake-selfie-image")
    );

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/users/me/verification-selfie",
      headers: {
        ...authHeader(me),
        "content-type": `multipart/form-data; boundary=${boundary}`
      },
      payload
    });

    expect(response.statusCode).toBe(200);
    expect(uploadVerificationSelfieObjectMock).toHaveBeenCalledWith(
      expect.stringMatching(new RegExp(`^${me}_\\d+\\.jpg$`)),
      expect.any(Buffer),
      "image/jpeg"
    );
    expect(extractFaceEmbeddingMock).not.toHaveBeenCalled();
    expect(enqueueSelfieEmbeddingJobMock).toHaveBeenCalledWith(
      me,
      expect.stringContaining(`/verification-selfies/${me}_`),
      expect.anything()
    );
    expect(verifyUploadedProfilePhotoMock).not.toHaveBeenCalled();
    expect(response.json()).toEqual({
      ok: true,
      selfieUrl: "https://cdn.example.com/selfie.jpg"
    });
    await app.close();
  });

  it("runs the photo comparison endpoint without updating verification state", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    extractFaceEmbeddingMock
      .mockResolvedValueOnce([1, 0, 0])
      .mockResolvedValueOnce([1, 0, 0]);

    const boundary = "----clubmates-test-debug-boundary";
    const payload = Buffer.concat([
      Buffer.from(
        `--${boundary}\r\nContent-Disposition: form-data; name="image1"; filename="image1.png"\r\nContent-Type: image/png\r\n\r\n`
      ),
      Buffer.from("image-one"),
      Buffer.from(`\r\n--${boundary}\r\nContent-Disposition: form-data; name="image2"; filename="image2.png"\r\nContent-Type: image/png\r\n\r\n`),
      Buffer.from("image-two"),
      Buffer.from(`\r\n--${boundary}--\r\n`)
    ]);

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/photos/compare",
      headers: {
        ...authHeader(me),
        "content-type": `multipart/form-data; boundary=${boundary}`
      },
      payload
    });

    expect(response.statusCode).toBe(200);
    expect(extractFaceEmbeddingMock).toHaveBeenCalledTimes(2);
    expect(verifyUploadedProfilePhotoMock).not.toHaveBeenCalled();
    expect(reevaluateUserFaceVerificationMock).not.toHaveBeenCalled();
    expect(response.json()).toEqual({
      ok: true,
      verification: {
        same_person: true,
        confidence: 100,
        distance: 0,
        threshold: 0.70,
        model: "ArcFace",
        detector_backend: "scrfd",
        similarity_metric: "cosine"
      }
    });
    await app.close();
  });

  it("re-evaluates verification when the photo order changes", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      return { rows: [], rowCount: 1 };
    });

    reevaluateUserFaceVerificationMock.mockResolvedValue({
      status: "rejected",
      isVerified: false,
      matched: false,
      confidence: 34.1,
      distance: 0.91,
      threshold: 0.70,
      model: "ArcFace",
      detectorBackend: "scrfd",
      similarityMetric: "cosine"
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "PUT",
      url: "/users/me/photos/order",
      headers: {
        ...authHeader(me),
        "content-type": "application/json"
      },
      payload: {
        order: ["photo-2", "photo-1"]
      }
    });

    expect(response.statusCode).toBe(200);
    expect(reevaluateUserFaceVerificationMock).not.toHaveBeenCalled();
    expect(verifyUserAgainstProfilePhotosMock).not.toHaveBeenCalled();
    expect(response.json()).toEqual({ ok: true });
    await app.close();
  });

  it("deletes omitted photos when saving a new authoritative photo order", async () => {
    const omittedStorageKey = `${me}/old-main-photo.jpg`;
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("DELETE FROM profile_photos") && sql.includes("NOT (id = ANY")) {
        return {
          rows: [{ storage_key: omittedStorageKey }],
          rowCount: 1
        };
      }
      if (sql.includes("SELECT face_embedding FROM users")) {
        return { rows: [{ face_embedding: [1, 0, 0] }], rowCount: 1 };
      }
      return { rows: [], rowCount: 1 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "PUT",
      url: "/users/me/photos/order",
      headers: {
        ...authHeader(me),
        "content-type": "application/json"
      },
      payload: {
        order: ["00000000-0000-0000-0000-000000000002"]
      }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ ok: true });
    expect(deleteProfilePhotoObjectsMock).toHaveBeenCalledWith([omittedStorageKey]);
    expect(verifyUserAgainstProfilePhotosMock).toHaveBeenCalledWith(me, expect.anything());
    await app.close();
  });
});
