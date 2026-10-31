import "dotenv/config";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const backendRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

export type AppEnv = {
  nodeEnv: string;
  host: string;
  port: number;
  databaseUrl: string;
  databaseSsl: boolean;
  jwtSecret: string;
  accessTokenTtlSeconds: number;
  refreshTokenDays: number;
  offlineCheckoutGraceMinutes: number;
  otpExpiryMinutes: number;
  devOtpCode?: string;
  msg91?: {
    authKey: string;
    templateId: string;
    senderId?: string;
    apiBaseUrl: string;
    timeoutMs: number;
  };
  supabase?: {
    url: string;
    serviceRoleKey: string;
    profilePhotosBucket: string;
    verificationSelfiesBucket: string;
    signedUrlTtlSeconds: number;
  };
  faceVerification?: {
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
  corsOrigin: string[];
  supabaseUrl?: string;
  supabaseServiceRoleKey?: string;
};

function required(name: string): string {
  const value = process.env[name];
  if (!value || value.trim().length === 0) {
    throw new Error(`Missing required environment variable ${name}`);
  }
  return value;
}

function numberEnv(name: string, fallback: number): number {
  const value = process.env[name];
  if (!value) { return fallback; }

  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    throw new Error(`Environment variable ${name} must be a number`);
  }
  return parsed;
}

function positiveNumberEnv(name: string, fallback: number): number {
  const parsed = numberEnv(name, fallback);
  if (parsed <= 0) {
    throw new Error(`Environment variable ${name} must be greater than 0`);
  }
  return parsed;
}

function optionalSecret(name: string, fallback: string): string {
  const value = process.env[name];
  if (value) { return value; }

  if (process.env.NODE_ENV === "production") {
    throw new Error(`Missing required production secret ${name}`);
  }

  return fallback;
}

function optionalTrimmed(name: string): string | undefined {
  const value = process.env[name]?.trim();
  return value ? value : undefined;
}

function supabaseConfig(): AppEnv["supabase"] {
  const url = optionalTrimmed("SUPABASE_URL")?.replace(/\/+$/, "");
  const serviceRoleKey = optionalTrimmed("SUPABASE_SERVICE_ROLE_KEY");
  const hasAnySupabaseStorageValue = !!url || !!serviceRoleKey;

  if (!hasAnySupabaseStorageValue) {
    return undefined;
  }

  if (!url || !serviceRoleKey) {
    throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required for storage features");
  }

  return {
    url,
    serviceRoleKey,
    profilePhotosBucket: optionalTrimmed("SUPABASE_PROFILE_PHOTOS_BUCKET") ?? "profile-photos",
    verificationSelfiesBucket: optionalTrimmed("SUPABASE_VERIFICATION_SELFIES_BUCKET") ?? "verification-selfies",
    signedUrlTtlSeconds: numberEnv("SUPABASE_SIGNED_URL_TTL_SECONDS", 60 * 60)
  };
}

function msg91Config(): AppEnv["msg91"] {
  const authKey = optionalTrimmed("MSG91_AUTH_KEY");
  const templateId = optionalTrimmed("MSG91_TEMPLATE_ID");
  const senderId = optionalTrimmed("MSG91_SENDER_ID");
  const hasAnyMsg91Value = !!authKey || !!templateId || !!senderId;

  if (!hasAnyMsg91Value) {
    if (process.env.NODE_ENV === "production") {
      throw new Error("MSG91_AUTH_KEY and MSG91_TEMPLATE_ID are required in production");
    }
    return undefined;
  }

  if (!authKey || !templateId) {
    throw new Error("MSG91_AUTH_KEY and MSG91_TEMPLATE_ID are required for MSG91 OTP delivery");
  }

  return {
    authKey,
    templateId,
    senderId,
    apiBaseUrl: (optionalTrimmed("MSG91_API_BASE_URL") ?? "https://control.msg91.com").replace(/\/+$/, ""),
    timeoutMs: positiveNumberEnv("MSG91_TIMEOUT_MS", 10_000)
  };
}

function faceVerificationConfig(): AppEnv["faceVerification"] {
  const localPythonBin = path.join(backendRoot, ".venv-face", "bin", "python");
  return {
    pythonBin: optionalTrimmed("FACE_VERIFICATION_PYTHON_BIN")
      ?? (existsSync(localPythonBin) ? localPythonBin : "python3"),
    embeddingScriptPath: optionalTrimmed("FACE_EMBEDDING_SCRIPT_PATH")
      ?? path.join(backendRoot, "scripts", "extract_embedding.py"),
    deepfaceHome: optionalTrimmed("FACE_VERIFICATION_DEEPFACE_HOME")
      ?? path.join(backendRoot, ".deepface-home"),
    model: optionalTrimmed("FACE_VERIFICATION_MODEL") ?? "ArcFace",
    detector: optionalTrimmed("FACE_VERIFICATION_DETECTOR") ?? "scrfd",
    distanceMetric: optionalTrimmed("FACE_VERIFICATION_DISTANCE_METRIC") ?? "cosine",
    threshold: numberEnv("FACE_VERIFICATION_THRESHOLD", 0.70),
    antiSpoofModelPath: optionalTrimmed("FACE_ANTI_SPOOF_MODEL_PATH")
      ?? path.join(backendRoot, "models", "minifasnet_v2.onnx"),
    antiSpoofThreshold: numberEnv("FACE_ANTI_SPOOF_THRESHOLD", 0.50),
    timeoutMs: numberEnv("FACE_VERIFICATION_TIMEOUT_MS", 120_000)
  };
}

export const env: AppEnv = {
  nodeEnv: process.env.NODE_ENV ?? "development",
  host: process.env.HOST ?? "0.0.0.0",
  port: numberEnv("PORT", 3000),
  databaseUrl: required("DATABASE_URL"),
  databaseSsl: process.env.DATABASE_SSL !== "false",
  jwtSecret: optionalSecret("JWT_SECRET", "dev-only-change-me"),
  accessTokenTtlSeconds: numberEnv("ACCESS_TOKEN_TTL_SECONDS", 900),
  refreshTokenDays: numberEnv("REFRESH_TOKEN_DAYS", 30),
  offlineCheckoutGraceMinutes: numberEnv("OFFLINE_CHECKOUT_GRACE_MINUTES", 20),
  otpExpiryMinutes: positiveNumberEnv("OTP_EXPIRY_MINUTES", 5),
  devOtpCode: process.env.DEV_OTP_CODE,
  msg91: msg91Config(),
  supabase: supabaseConfig(),
  faceVerification: faceVerificationConfig(),
  corsOrigin: (process.env.CORS_ORIGIN ?? "*")
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean),
  supabaseUrl: process.env.SUPABASE_URL || undefined,
  supabaseServiceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY || undefined
};
