import { beforeEach, vi } from "vitest";
import { hashValue } from "../../src/utils/crypto.js";

const { queryMock, withTransactionMock } = vi.hoisted(() => ({
  queryMock: vi.fn(),
  withTransactionMock: vi.fn()
}));

vi.mock("../../src/db/pool.js", () => ({
  query: queryMock,
  withTransaction: withTransactionMock,
  closePool: vi.fn()
}));

vi.mock("../../src/jobs/accountDeletion.js", () => ({
  purgeExpiredDeletedUsers: vi.fn(async () => 0),
  registerAccountDeletionPurge: vi.fn()
}));

vi.mock("../../src/realtime/chatHub.js", () => ({
  configureRealtimeLogger: vi.fn(),
  registerRealtimeConnection: vi.fn(),
  broadcastToUser: vi.fn(),
  disconnectRealtimeUser: vi.fn()
}));

vi.mock("../../src/services/profilePhotoStorage.js", () => ({
  deleteProfilePhotoObjects: vi.fn(),
  deleteProfilePhotoObject: vi.fn(),
  uploadProfilePhoto: vi.fn()
}));

import { buildApp } from "../../src/app.js";

const phone = "+919876543210";
const userId = "505f7fc3-2d06-4b96-aa90-6380f511ffde";
const deletionScheduledAt = new Date("2026-06-05T10:00:00.000Z");

function scheduledUser(profileCompleted = true) {
  return {
    id: userId,
    phone_e164: phone,
    profile_completed: profileCompleted,
    is_active: false,
    deletion_requested_at: new Date("2026-06-04T10:00:00.000Z"),
    deletion_scheduled_at: deletionScheduledAt
  };
}

describe("account restore auth flow", () => {
  beforeEach(() => {
    queryMock.mockReset();
    withTransactionMock.mockReset();

    withTransactionMock.mockImplementation(async (cb: (client: { query: typeof queryMock }) => Promise<unknown>) => {
      return cb({ query: queryMock });
    });
  });

  it("reports pending deletion status for a returning phone number", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT id, phone_e164, profile_completed")) {
        return { rows: [scheduledUser()], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/auth/account-status",
      payload: { phone }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({
      userExists: true,
      deletionScheduledAt: deletionScheduledAt.toISOString()
    });
    await app.close();
  });

  it("blocks normal OTP for accounts scheduled for deletion", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT id, phone_e164, profile_completed")) {
        return { rows: [scheduledUser()], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/auth/otp/send",
      payload: { phone }
    });

    expect(response.statusCode).toBe(403);
    expect(response.json()).toEqual({ error: "Account deletion is scheduled" });
    expect(queryMock).not.toHaveBeenCalledWith(expect.stringContaining("INSERT INTO otp_codes"), expect.anything());
    await app.close();
  });

  it("allows restore OTP and restores account after OTP verification", async () => {
    const otpCode = "123456";
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT id, phone_e164, profile_completed")) {
        return { rows: [scheduledUser()], rowCount: 1 };
      }
      if (sql.includes("INSERT INTO otp_codes")) {
        return { rows: [], rowCount: 1 };
      }
      if (sql.includes("SELECT code_hash, expires_at, attempts FROM otp_codes")) {
        return {
          rows: [{
            code_hash: hashValue(`${phone}:${otpCode}`),
            expires_at: new Date(Date.now() + 60_000),
            attempts: 0
          }],
          rowCount: 1
        };
      }
      if (sql.includes("DELETE FROM otp_codes")) {
        return { rows: [], rowCount: 1 };
      }
      if (sql.includes("INSERT INTO users(phone_e164)")) {
        return {
          rows: [{
            id: userId,
            phone_e164: phone,
            profile_completed: true
          }],
          rowCount: 1
        };
      }
      if (sql.includes("INSERT INTO refresh_tokens")) {
        return { rows: [], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();

    const sendResponse = await app.inject({
      method: "POST",
      url: "/auth/otp/send",
      payload: { phone, restore: true }
    });
    expect(sendResponse.statusCode).toBe(200);
    expect(sendResponse.json()).toMatchObject({
      ok: true,
      userExists: true,
      deletionScheduledAt: deletionScheduledAt.toISOString()
    });

    const verifyResponse = await app.inject({
      method: "POST",
      url: "/auth/otp/verify",
      payload: { phone, code: otpCode, restore: true }
    });

    expect(verifyResponse.statusCode).toBe(200);
    expect(verifyResponse.json()).toMatchObject({
      user: {
        id: userId,
        phone,
        profileCompleted: true
      },
      isNewUser: false,
      restored: true
    });
    expect(queryMock).toHaveBeenCalledWith(
      expect.stringContaining("deletion_requested_at = NULL"),
      [phone]
    );
    await app.close();
  });
});
