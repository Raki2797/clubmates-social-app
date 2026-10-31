import { env } from "../config/env.js";

type SignedUrlResponse = {
  signedURL?: string;
  signedUrl?: string;
  error?: string;
  message?: string;
};

type StorageErrorResponse = {
  error?: string;
  message?: string;
};

export class ProfilePhotoStorageError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ProfilePhotoStorageError";
  }
}

const storageRequestTimeoutMs = 15_000;
const storageRequestAttempts = 2;

function storageConfig() {
  if (!env.supabase) {
    throw new ProfilePhotoStorageError("Supabase Storage is not configured");
  }

  return env.supabase;
}

function storageHeaders(contentType?: string): HeadersInit {
  const config = storageConfig();
  return {
    apikey: config.serviceRoleKey,
    Authorization: `Bearer ${config.serviceRoleKey}`,
    ...(contentType ? { "Content-Type": contentType } : {})
  };
}

async function readStorageResponse(response: Response): Promise<unknown> {
  const text = await response.text();
  if (!text) {
    return undefined;
  }

  try {
    return JSON.parse(text) as unknown;
  } catch {
    return text;
  }
}

function storageErrorMessage(body: unknown): string {
  if (body && typeof body === "object") {
    const payload = body as StorageErrorResponse;
    return payload.message ?? payload.error ?? "Unknown storage error";
  }

  return typeof body === "string" ? body : "Unknown storage error";
}

type StorageBucket = "profilePhotos" | "verificationSelfies";

function bucketName(bucket: StorageBucket): string {
  const config = storageConfig();
  return bucket === "verificationSelfies"
    ? config.verificationSelfiesBucket
    : config.profilePhotosBucket;
}

function objectUrl(storageKey: string, bucket: StorageBucket = "profilePhotos"): string {
  const config = storageConfig();
  const encodedBucket = encodeURIComponent(bucketName(bucket));
  return `${config.url}/storage/v1/object/${encodedBucket}/${storageKey}`;
}

export function authenticatedPhotoUrl(storageKey: string): string | undefined {
  if (!env.supabase) {
    return undefined;
  }
  return objectUrl(storageKey);
}

export function authenticatedVerificationSelfieUrl(storageKey: string): string | undefined {
  if (!env.supabase) {
    return undefined;
  }
  return objectUrl(storageKey, "verificationSelfies");
}

function normalizeSignedUrl(url: string): string {
  if (url.includes("/storage/v1/object/sign/")) {
    return url;
  }
  if (url.includes("/object/sign/")) {
    return url.replace("/object/sign/", "/storage/v1/object/sign/");
  }
  return url;
}

function isRetryableStorageStatus(status: number): boolean {
  return status === 408 || status === 429 || status >= 500;
}

async function waitBeforeStorageRetry(attempt: number): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, 250 * 2 ** attempt));
}

async function storageFetch(
  url: string,
  init: RequestInit,
  operation: string
): Promise<Response> {
  let lastError: unknown;

  for (let attempt = 0; attempt < storageRequestAttempts; attempt += 1) {
    try {
      const response = await fetch(url, {
        ...init,
        signal: AbortSignal.timeout(storageRequestTimeoutMs)
      });

      if (
        response.ok
        || !isRetryableStorageStatus(response.status)
        || attempt === storageRequestAttempts - 1
      ) {
        return response;
      }

      await response.body?.cancel();
    } catch (error) {
      lastError = error;
      if (attempt === storageRequestAttempts - 1) {
        break;
      }
    }

    await waitBeforeStorageRetry(attempt);
  }

  const reason = lastError instanceof Error ? lastError.message : "request timed out";
  throw new ProfilePhotoStorageError(
    `Supabase ${operation} failed after ${storageRequestAttempts} attempts: ${reason}`
  );
}

export async function uploadProfilePhotoObject(
  storageKey: string,
  body: Buffer,
  contentType: string
): Promise<void> {
  const response = await storageFetch(objectUrl(storageKey), {
    method: "PUT",
    headers: {
      ...storageHeaders(contentType),
      "x-upsert": "true",
      "Cache-Control": "3600"
    },
    body: body as unknown as BodyInit
  }, "photo upload");

  if (!response.ok) {
    const payload = await readStorageResponse(response);
    throw new ProfilePhotoStorageError(
      `Supabase photo upload failed: ${response.status} ${storageErrorMessage(payload)}`
    );
  }
}

export async function uploadVerificationSelfieObject(
  storageKey: string,
  body: Buffer,
  contentType: string
): Promise<void> {
  const response = await storageFetch(objectUrl(storageKey, "verificationSelfies"), {
    method: "PUT",
    headers: {
      ...storageHeaders(contentType),
      "x-upsert": "true",
      "Cache-Control": "3600"
    },
    body: body as unknown as BodyInit
  }, "selfie upload");

  if (!response.ok) {
    const payload = await readStorageResponse(response);
    throw new ProfilePhotoStorageError(
      `Supabase selfie upload failed: ${response.status} ${storageErrorMessage(payload)}`
    );
  }
}

export async function downloadProfilePhotoObject(storageKey: string): Promise<Buffer | undefined> {
  const response = await storageFetch(objectUrl(storageKey), {
    method: "GET",
    headers: storageHeaders()
  }, "photo download");

  if (response.status === 404) {
    await response.body?.cancel();
    return undefined;
  }

  if (!response.ok) {
    const payload = await readStorageResponse(response);
    throw new ProfilePhotoStorageError(
      `Supabase photo download failed: ${response.status} ${storageErrorMessage(payload)}`
    );
  }

  return Buffer.from(await response.arrayBuffer());
}

export async function deleteProfilePhotoObjects(storageKeys: string[]): Promise<void> {
  if (!env.supabase || storageKeys.length === 0) {
    return;
  }

  const config = storageConfig();
  const bucket = encodeURIComponent(config.profilePhotosBucket);
  const response = await storageFetch(`${config.url}/storage/v1/object/${bucket}`, {
    method: "DELETE",
    headers: storageHeaders("application/json"),
    body: JSON.stringify({ prefixes: storageKeys })
  }, "photo delete");

  if (!response.ok) {
    const payload = await readStorageResponse(response);
    throw new ProfilePhotoStorageError(
      `Supabase photo delete failed: ${response.status} ${storageErrorMessage(payload)}`
    );
  }
}

export async function signedProfilePhotoUrl(storageKey: string): Promise<string | undefined> {
  return signedStorageObjectUrl(storageKey, "profilePhotos");
}

export async function signedVerificationSelfieUrl(storageKey: string): Promise<string | undefined> {
  return signedStorageObjectUrl(storageKey, "verificationSelfies");
}

async function signedStorageObjectUrl(storageKey: string, bucket: StorageBucket): Promise<string | undefined> {
  if (!env.supabase) {
    return undefined;
  }

  const config = storageConfig();
  const encodedBucket = encodeURIComponent(bucketName(bucket));
  const response = await storageFetch(`${config.url}/storage/v1/object/sign/${encodedBucket}/${storageKey}`, {
    method: "POST",
    headers: storageHeaders("application/json"),
    body: JSON.stringify({ expiresIn: config.signedUrlTtlSeconds })
  }, "signed URL");

  const payload = await readStorageResponse(response);
  if (!response.ok) {
    const isMissingObject = response.status === 400
      && typeof payload === "object"
      && payload !== null
      && storageErrorMessage(payload).toLowerCase().includes("object not found");

    if (isMissingObject) {
      return undefined;
    }

    throw new ProfilePhotoStorageError(
      `Supabase signed URL failed: ${response.status} ${storageErrorMessage(payload)}`
    );
  }

  if (payload && typeof payload === "object") {
    const signed = payload as SignedUrlResponse;
    const path = signed.signedURL ?? signed.signedUrl;
    if (!path) {
      return undefined;
    }

    const absolute = new URL(path, `${config.url}/storage/v1/`).toString();
    return normalizeSignedUrl(absolute);
  }

  return undefined;
}

export async function withSignedPhotoUrl<T extends { storage_key: string; cdn_url: string | null }>(
  photo: T
): Promise<T> {
  const signedUrl = await signedProfilePhotoUrl(photo.storage_key);
  return {
    ...photo,
    cdn_url: signedUrl ?? photo.cdn_url
  };
}

export async function withSignedPhotoUrls<T extends { storage_key: string; cdn_url: string | null }>(
  photos: T[]
): Promise<T[]> {
  return Promise.all(photos.map((photo) => withSignedPhotoUrl(photo)));
}
