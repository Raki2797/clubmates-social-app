import { beforeEach, vi } from "vitest";

process.env.NODE_ENV = process.env.NODE_ENV ?? "test";
process.env.DATABASE_URL = process.env.DATABASE_URL ?? "postgresql://postgres:postgres@localhost:5432/clubmates_test";
process.env.JWT_SECRET = process.env.JWT_SECRET ?? "test-secret";
process.env.ACCESS_TOKEN_TTL_SECONDS = process.env.ACCESS_TOKEN_TTL_SECONDS ?? "900";
process.env.REFRESH_TOKEN_DAYS = process.env.REFRESH_TOKEN_DAYS ?? "30";
process.env.DATABASE_SSL = process.env.DATABASE_SSL ?? "false";
process.env.OTP_EXPIRY_MINUTES = process.env.OTP_EXPIRY_MINUTES ?? "5";
process.env.DEV_OTP_CODE = process.env.DEV_OTP_CODE ?? "123456";
process.env.MSG91_AUTH_KEY = "";
process.env.MSG91_TEMPLATE_ID = "";
process.env.MSG91_SENDER_ID = "";
process.env.MSG91_API_BASE_URL = "";
process.env.MSG91_TIMEOUT_MS = "";

// Keep tests deterministic and avoid leaking state between suites.
beforeEach(() => {
  vi.restoreAllMocks();
});
