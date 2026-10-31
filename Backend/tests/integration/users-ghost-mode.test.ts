import { beforeEach, vi } from "vitest";
import { signAccessToken } from "../../src/utils/auth.js";

const { queryMock, withTransactionMock } = vi.hoisted(() => ({
  queryMock: vi.fn(),
  withTransactionMock: vi.fn()
}));

const { withSignedPhotoUrlsMock } = vi.hoisted(() => ({
  withSignedPhotoUrlsMock: vi.fn(async (photos: unknown[]) => photos)
}));

vi.mock("../../src/db/pool.js", () => ({
  query: queryMock,
  withTransaction: withTransactionMock,
  closePool: vi.fn()
}));

vi.mock("../../src/services/profilePhotoStorage.js", () => ({
  withSignedPhotoUrls: withSignedPhotoUrlsMock,
  signedProfilePhotoUrl: vi.fn(),
  uploadProfilePhotoObject: vi.fn(),
  deleteProfilePhotoObjects: vi.fn()
}));

import { buildApp } from "../../src/app.js";

const me = "505f7fc3-2d06-4b96-aa90-6380f511ffde";

function authHeader(userId: string): Record<string, string> {
  const token = signAccessToken({ userId, phone: "+911234567890" });
  return { authorization: `Bearer ${token}` };
}

function profileRow(isGhostMode: boolean) {
  return {
    id: me,
    phone_e164: "+911234567890",
    name: "Sai",
    age: 28,
    bio: "Hello",
    profession: "Engineer",
    gender: "Male",
    height: 176,
    interests: ["Music"],
    is_verified: false,
    is_ghost_mode: isGhostMode,
    profile_completed: true,
    verification_selfie_url: null,
    looking_for: "Dating",
    pref_age_min: 18,
    pref_age_max: 60,
    pref_genders: [],
    pref_height_min: 140,
    pref_height_max: 220,
    pref_verified_only: false,
    notif_enabled: true,
    notif_new_match: true,
    notif_new_message: true,
    notif_liked_you: true,
    notif_super_like: true,
    notif_venue_activity: true
  };
}

describe("users ghost mode", () => {
  beforeEach(() => {
    queryMock.mockReset();
    withTransactionMock.mockReset();
    withSignedPhotoUrlsMock.mockClear();
    withTransactionMock.mockImplementation(
      async (callback: (client: { query: typeof queryMock }) => Promise<unknown>) => callback({ query: queryMock })
    );
  });

  it("persists ghost mode from PATCH /users/me and returns it in the profile", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("UPDATE users SET")) {
        return { rows: [], rowCount: 1 };
      }
      if (sql.includes("FROM users") && sql.includes("WHERE id = $1")) {
        return { rows: [profileRow(true)], rowCount: 1 };
      }
      if (sql.includes("FROM profile_prompts") || sql.includes("FROM profile_photos")) {
        return { rows: [], rowCount: 0 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "PATCH",
      url: "/users/me",
      headers: authHeader(me),
      payload: { isGhostMode: true }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json().user.isGhostMode).toBe(true);
    expect(queryMock).toHaveBeenCalledWith(
      expect.stringContaining("is_ghost_mode = $2"),
      [me, true]
    );
    await app.close();
  });

  it("includes ghost mode on GET /users/me", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM users") && sql.includes("WHERE id = $1")) {
        return { rows: [profileRow(false)], rowCount: 1 };
      }
      if (sql.includes("FROM profile_prompts") || sql.includes("FROM profile_photos")) {
        return { rows: [], rowCount: 0 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "GET",
      url: "/users/me",
      headers: authHeader(me)
    });

    expect(response.statusCode).toBe(200);
    expect(response.json().user.isGhostMode).toBe(false);
    await app.close();
  });
});
