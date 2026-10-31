import { FastifyInstance } from "fastify";
import { env } from "../config/env.js";
import { query, withTransaction } from "../db/pool.js";
import { purgeExpiredDeletedUsers } from "../jobs/accountDeletion.js";
import { disconnectRealtimeUser } from "../realtime/chatHub.js";
import { deliverOtp } from "../services/otpDelivery.js";
import { hashValue, randomOtp, randomToken } from "../utils/crypto.js";
import { asString, sendError } from "../utils/http.js";
import { assertValidPhone, normalizePhone } from "../utils/phone.js";
import { signAccessToken } from "../utils/auth.js";

type AuthUserRow = {
  id: string;
  phone_e164: string;
  profile_completed: boolean;
};

type ExistingAuthUserRow = AuthUserRow & {
  is_active: boolean;
  deletion_requested_at: Date | null;
  deletion_scheduled_at: Date | null;
};

async function findExistingUser(phone: string): Promise<ExistingAuthUserRow | undefined> {
  await purgeExpiredDeletedUsers();

  const existingUser = await query<ExistingAuthUserRow>(
    `
      SELECT id, phone_e164, profile_completed, is_active, deletion_requested_at, deletion_scheduled_at
      FROM users
      WHERE phone_e164 = $1
    `,
    [phone]
  );

  return existingUser.rows[0];
}

function isScheduledForDeletion(row: ExistingAuthUserRow | undefined): boolean {
  return !!row?.deletion_scheduled_at;
}

function isInactiveDeletedAccount(row: ExistingAuthUserRow | undefined): boolean {
  return !!row && !row.is_active && !row.deletion_scheduled_at;
}

function shouldReturnDevOtpCode(): boolean {
  return env.nodeEnv !== "production" && !env.msg91;
}

function nextOtpCode(): string {
  return shouldReturnDevOtpCode() && env.devOtpCode ? env.devOtpCode : randomOtp();
}

async function persistRefreshToken(userId: string): Promise<string> {
  const refreshToken = randomToken(48);
  const tokenHash = hashValue(refreshToken);
  await query(
    `
      INSERT INTO refresh_tokens(token_hash, user_id, expires_at)
      VALUES ($1, $2, now() + ($3::text || ' days')::interval)
    `,
    [tokenHash, userId, env.refreshTokenDays]
  );
  return refreshToken;
}

async function sessionPayload(user: AuthUserRow) {
  const accessToken = signAccessToken({
    userId: user.id,
    phone: user.phone_e164
  });
  const refreshToken = await persistRefreshToken(user.id);

  return {
    accessToken,
    refreshToken,
    user: {
      id: user.id,
      phone: user.phone_e164,
      profileCompleted: user.profile_completed
    }
  };
}

export async function authRoutes(app: FastifyInstance): Promise<void> {
  app.post<{ Body: { phone?: string } }>("/auth/account-status", async (request, reply) => {
    const rawPhone = asString(request.body?.phone);
    if (!rawPhone) {
      return sendError(reply, 400, "phone is required");
    }

    const phone = normalizePhone(rawPhone);
    try {
      assertValidPhone(phone);
    } catch (error) {
      return sendError(reply, 400, error instanceof Error ? error.message : "Invalid phone");
    }

    const existingUser = await findExistingUser(phone);
    return {
      userExists: !!existingUser,
      deletionScheduledAt: existingUser?.deletion_scheduled_at?.toISOString() ?? null
    };
  });

  app.post<{ Body: { phone?: string; restore?: boolean } }>("/auth/otp/send", async (request, reply) => {
    const rawPhone = asString(request.body?.phone);
    if (!rawPhone) {
      return sendError(reply, 400, "phone is required");
    }

    const phone = normalizePhone(rawPhone);
    try {
      assertValidPhone(phone);
    } catch (error) {
      return sendError(reply, 400, error instanceof Error ? error.message : "Invalid phone");
    }

    const existingUser = await findExistingUser(phone);
    const isRestoreRequest = request.body?.restore === true;

    if (isScheduledForDeletion(existingUser) && !isRestoreRequest) {
      return sendError(reply, 403, "Account deletion is scheduled");
    }

    if (isInactiveDeletedAccount(existingUser)) {
      return sendError(reply, 403, "Account is no longer available");
    }

    const userExists = !!existingUser;

    const code = nextOtpCode();
    const codeHash = hashValue(`${phone}:${code}`);
    await query(
      `
        INSERT INTO otp_codes(phone_e164, code_hash, expires_at, attempts)
        VALUES ($1, $2, now() + ($3::text || ' minutes')::interval, 0)
        ON CONFLICT (phone_e164)
        DO UPDATE SET code_hash = EXCLUDED.code_hash,
                      expires_at = EXCLUDED.expires_at,
                      attempts = 0,
                      created_at = now()
      `,
      [phone, codeHash, env.otpExpiryMinutes]
    );

    try {
      await deliverOtp(phone, code);
    } catch (error) {
      try {
        await query(
          "DELETE FROM otp_codes WHERE phone_e164 = $1 AND code_hash = $2",
          [phone, codeHash]
        );
      } catch (cleanupError) {
        app.log.error({ err: cleanupError, phone }, "OTP cleanup failed after delivery error");
      }
      app.log.error({ err: error, phone }, "OTP delivery failed");
      return sendError(reply, 502, "Could not send OTP. Please try again.");
    }

    return {
      ok: true,
      userExists,
      deletionScheduledAt: existingUser?.deletion_scheduled_at?.toISOString() ?? null,
      ...(shouldReturnDevOtpCode() ? { devCode: code } : {})
    };
  });

  app.post<{ Body: { phone?: string; code?: string; restore?: boolean } }>("/auth/otp/verify", async (request, reply) => {
    const rawPhone = asString(request.body?.phone);
    const rawCode = asString(request.body?.code);
    if (!rawPhone || !rawCode) {
      return sendError(reply, 400, "phone and code are required");
    }

    const phone = normalizePhone(rawPhone);
    const code = rawCode.trim();
    const isRestoreRequest = request.body?.restore === true;

    try {
      assertValidPhone(phone);
    } catch (error) {
      return sendError(reply, 400, error instanceof Error ? error.message : "Invalid phone");
    }

    if (!/^\d{6}$/.test(code)) {
      return sendError(reply, 400, "OTP must be a 6-digit code");
    }

    const existingUser = await findExistingUser(phone);
    const shouldRestore = isScheduledForDeletion(existingUser);

    if (shouldRestore && !isRestoreRequest) {
      return sendError(reply, 403, "Account deletion is scheduled");
    }

    if (isInactiveDeletedAccount(existingUser)) {
      return sendError(reply, 403, "Account is no longer available");
    }

    const otp = await query<{
      code_hash: string;
      expires_at: Date;
      attempts: number;
    }>(
      "SELECT code_hash, expires_at, attempts FROM otp_codes WHERE phone_e164 = $1",
      [phone]
    );

    const row = otp.rows[0];
    if (!row || row.expires_at.getTime() < Date.now() || row.attempts >= 5) {
      return sendError(reply, 401, "OTP is invalid or expired");
    }

    if (row.code_hash !== hashValue(`${phone}:${code}`)) {
      await query("UPDATE otp_codes SET attempts = attempts + 1 WHERE phone_e164 = $1", [phone]);
      return sendError(reply, 401, "OTP is invalid or expired");
    }

    const user = await withTransaction<AuthUserRow>(async (client) => {
      await client.query("DELETE FROM otp_codes WHERE phone_e164 = $1", [phone]);
      const result = await client.query<AuthUserRow>(
        `
          INSERT INTO users(phone_e164)
          VALUES ($1)
          ON CONFLICT (phone_e164)
          DO UPDATE SET updated_at = now(),
                        is_active = true,
                        deletion_requested_at = NULL,
                        deletion_scheduled_at = NULL
          RETURNING id, phone_e164, profile_completed
        `,
        [phone]
      );
      return result.rows[0];
    });

    const payload = await sessionPayload(user);
    return {
      ...payload,
      isNewUser: !user.profile_completed,
      restored: shouldRestore
    };
  });

  app.post<{ Body: { refreshToken?: string } }>("/auth/refresh", async (request, reply) => {
    const refreshToken = asString(request.body?.refreshToken);
    if (!refreshToken) {
      return sendError(reply, 400, "refreshToken is required");
    }

    const tokenHash = hashValue(refreshToken);
    const user = await withTransaction<AuthUserRow | undefined>(async (client) => {
      const token = await client.query<{ user_id: string }>(
        `
          SELECT user_id
          FROM refresh_tokens
          WHERE token_hash = $1
            AND revoked_at IS NULL
            AND expires_at > now()
          FOR UPDATE
        `,
        [tokenHash]
      );
      const tokenRow = token.rows[0];
      if (!tokenRow) {
        return undefined;
      }

      await client.query("UPDATE refresh_tokens SET revoked_at = now() WHERE token_hash = $1", [tokenHash]);
      const userResult = await client.query<AuthUserRow>(
        `
          SELECT id, phone_e164, profile_completed
          FROM users
          WHERE id = $1
            AND is_active = true
            AND deletion_scheduled_at IS NULL
        `,
        [tokenRow.user_id]
      );
      return userResult.rows[0];
    });

    if (!user) {
      return sendError(reply, 401, "Refresh token is invalid or expired");
    }

    return sessionPayload(user);
  });

  app.delete<{ Body: { refreshToken?: string } }>("/auth/session", async (request) => {
    const refreshToken = asString(request.body?.refreshToken);
    if (refreshToken) {
      const tokenHash = hashValue(refreshToken);
      const tokenOwner = await query<{ user_id: string }>(
        "SELECT user_id FROM refresh_tokens WHERE token_hash = $1 LIMIT 1",
        [tokenHash]
      );

      await query("UPDATE refresh_tokens SET revoked_at = now() WHERE token_hash = $1", [tokenHash]);

      const userId = tokenOwner.rows[0]?.user_id;
      if (userId) {
        await query(
          `
            UPDATE checkins
            SET checked_out_at = now()
            WHERE user_id = $1
              AND checked_out_at IS NULL
          `,
          [userId]
        );
        disconnectRealtimeUser(userId);
      }
    }
    return { ok: true };
  });
}
