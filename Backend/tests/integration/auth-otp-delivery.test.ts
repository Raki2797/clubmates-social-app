import { beforeEach, vi } from "vitest";
import { hashValue } from "../../src/utils/crypto.js";

const { queryMock } = vi.hoisted(() => ({
  queryMock: vi.fn()
}));

const { deliverOtpMock } = vi.hoisted(() => ({
  deliverOtpMock: vi.fn()
}));

vi.mock("../../src/db/pool.js", () => ({
  query: queryMock,
  withTransaction: vi.fn(),
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

vi.mock("../../src/services/otpDelivery.js", () => ({
  deliverOtp: deliverOtpMock
}));

const phone = "+919876543210";

async function buildAppWithMsg91() {
  vi.resetModules();
  process.env.MSG91_AUTH_KEY = "auth-key";
  process.env.MSG91_TEMPLATE_ID = "template-id";
  process.env.MSG91_SENDER_ID = "TAARVN";
  process.env.OTP_EXPIRY_MINUTES = "5";
  const { buildApp } = await import("../../src/app.js");
  return buildApp();
}

describe("auth OTP delivery", () => {
  beforeEach(() => {
    queryMock.mockReset();
    deliverOtpMock.mockReset();
  });

  it("stores and delivers a random OTP without exposing a dev code when MSG91 is configured", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT id, phone_e164, profile_completed")) {
        return { rows: [], rowCount: 0 };
      }
      if (sql.includes("INSERT INTO otp_codes")) {
        return { rows: [], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });
    deliverOtpMock.mockResolvedValue(undefined);

    const app = await buildAppWithMsg91();
    const response = await app.inject({
      method: "POST",
      url: "/auth/otp/send",
      payload: { phone }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({
      ok: true,
      userExists: false,
      deletionScheduledAt: null
    });

    expect(deliverOtpMock).toHaveBeenCalledTimes(1);
    const deliveredCode = deliverOtpMock.mock.calls[0][1] as string;
    expect(deliveredCode).toMatch(/^\d{6}$/);
    expect(queryMock).toHaveBeenCalledWith(
      expect.stringContaining("INSERT INTO otp_codes"),
      [phone, hashValue(`${phone}:${deliveredCode}`), 5]
    );
    await app.close();
  });

  it("removes the stored OTP and returns a retryable error when delivery fails", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT id, phone_e164, profile_completed")) {
        return { rows: [], rowCount: 0 };
      }
      if (sql.includes("INSERT INTO otp_codes")) {
        return { rows: [], rowCount: 1 };
      }
      if (sql.includes("DELETE FROM otp_codes")) {
        return { rows: [], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });
    deliverOtpMock.mockRejectedValue(new Error("MSG91 unavailable"));

    const app = await buildAppWithMsg91();
    const response = await app.inject({
      method: "POST",
      url: "/auth/otp/send",
      payload: { phone }
    });

    expect(response.statusCode).toBe(502);
    expect(response.json()).toEqual({ error: "Could not send OTP. Please try again." });
    const deliveredCode = deliverOtpMock.mock.calls[0][1] as string;
    expect(queryMock).toHaveBeenCalledWith(
      "DELETE FROM otp_codes WHERE phone_e164 = $1 AND code_hash = $2",
      [phone, hashValue(`${phone}:${deliveredCode}`)]
    );
    await app.close();
  });
});
