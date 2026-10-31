import { beforeEach, vi } from "vitest";
import { signAccessToken } from "../../src/utils/auth.js";

const { queryMock } = vi.hoisted(() => ({
  queryMock: vi.fn()
}));

const { withSignedPhotoUrlsMock } = vi.hoisted(() => ({
  withSignedPhotoUrlsMock: vi.fn()
}));

vi.mock("../../src/db/pool.js", () => ({
  query: queryMock,
  withTransaction: vi.fn(),
  closePool: vi.fn()
}));

vi.mock("../../src/services/profilePhotoStorage.js", () => ({
  withSignedPhotoUrls: withSignedPhotoUrlsMock,
  signedProfilePhotoUrl: vi.fn(),
  uploadProfilePhotoObject: vi.fn(),
  deleteProfilePhotoObjects: vi.fn()
}));

import { buildApp } from "../../src/app.js";

function authHeader(userId: string): Record<string, string> {
  const token = signAccessToken({ userId, phone: "+911234567890" });
  return { authorization: `Bearer ${token}` };
}

describe("users public profile", () => {
  beforeEach(() => {
    queryMock.mockReset();
    withSignedPhotoUrlsMock.mockReset();
    withSignedPhotoUrlsMock.mockImplementation(async (photos: unknown[]) => photos);
  });

  it("returns full profile for eligible roster-visible user without phone", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("SELECT EXISTS (") && sql.includes("FROM users target")) {
        return { rows: [{ visible: true }], rowCount: 1 };
      }
      if (sql.includes("FROM users") && sql.includes("WHERE id = $1")) {
        return {
          rows: [{
            id: "4f34e495-a51f-498c-86a9-5c2cba3a9e5a",
            phone_e164: "+919999999999",
            name: "Dhanush",
            age: 21,
            bio: "Tester",
            profession: "Chef",
            gender: "Male",
            height: 171,
            interests: ["Travel"],
            is_verified: false,
            profile_completed: true,
            verification_selfie_url: null,
            looking_for: "Dating",
            pref_age_min: 20,
            pref_age_max: 30,
            pref_genders: ["Female"],
            pref_height_min: 155,
            pref_height_max: 180,
            pref_verified_only: false,
            notif_enabled: true,
            notif_new_match: true,
            notif_new_message: true,
            notif_liked_you: true,
            notif_super_like: false,
            notif_venue_activity: true
          }],
          rowCount: 1
        };
      }
      if (sql.includes("FROM profile_prompts")) {
        return {
          rows: [{
            id: "c436f088-b627-4226-9ec0-09b2bfe2a5f2",
            question: "Weekend?",
            answer: "Road trip",
            position: 0
          }],
          rowCount: 1
        };
      }
      if (sql.includes("FROM profile_photos")) {
        return {
          rows: [{
            id: "9e59be5a-d91c-4f29-b3ca-4cfe5545ea65",
            storage_key: "users/dhanush/main.jpg",
            cdn_url: "https://cdn.example.com/dhanush.jpg",
            position: 0
          }],
          rowCount: 1
        };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "GET",
      url: "/users/4f34e495-a51f-498c-86a9-5c2cba3a9e5a/profile",
      headers: authHeader("505f7fc3-2d06-4b96-aa90-6380f511ffde")
    });

    expect(response.statusCode).toBe(200);
    const body = response.json();
    expect(body.user.id).toBe("4f34e495-a51f-498c-86a9-5c2cba3a9e5a");
    expect(body.user.phone).toBeUndefined();
    expect(body.user.prompts).toHaveLength(1);
    expect(body.user.photos).toHaveLength(1);
    expect(body.user.lookingFor).toBe("Dating");
    expect(body.user.preferences).toEqual({
      ageMin: 20,
      ageMax: 30,
      genders: ["Female"],
      heightMin: 155,
      heightMax: 180,
      verifiedOnly: false
    });
    expect(body.user.notificationPreferences).toEqual({
      enabled: true,
      newMatch: true,
      newMessage: true,
      likedYou: true,
      superLike: false,
      venueActivity: true
    });
    await app.close();
  });

  it("returns 404 when target profile is not visible", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("SELECT EXISTS (") && sql.includes("FROM users target")) {
        return { rows: [{ visible: false }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "GET",
      url: "/users/4f34e495-a51f-498c-86a9-5c2cba3a9e5a/profile",
      headers: authHeader("505f7fc3-2d06-4b96-aa90-6380f511ffde")
    });

    expect(response.statusCode).toBe(404);
    await app.close();
  });
});
