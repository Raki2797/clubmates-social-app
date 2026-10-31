import { beforeEach, vi } from "vitest";
import { signAccessToken } from "../../src/utils/auth.js";

const { queryMock } = vi.hoisted(() => ({
  queryMock: vi.fn()
}));

const { signedProfilePhotoUrlMock } = vi.hoisted(() => ({
  signedProfilePhotoUrlMock: vi.fn()
}));

vi.mock("../../src/db/pool.js", () => ({
  query: queryMock,
  withTransaction: vi.fn(),
  closePool: vi.fn()
}));

const { withSignedPhotoUrlsMock } = vi.hoisted(() => ({
  withSignedPhotoUrlsMock: vi.fn()
}));

vi.mock("../../src/services/profilePhotoStorage.js", () => ({
  signedProfilePhotoUrl: signedProfilePhotoUrlMock,
  withSignedPhotoUrls: withSignedPhotoUrlsMock
}));

import { buildApp } from "../../src/app.js";

function authHeader(userId: string): Record<string, string> {
  const token = signAccessToken({ userId, phone: "+911234567890" });
  return { authorization: `Bearer ${token}` };
}

const me = "505f7fc3-2d06-4b96-aa90-6380f511ffde";
const liker = "4f34e495-a51f-498c-86a9-5c2cba3a9e5a";
const venueId = "abf264f1-6cea-4cb9-bdaf-a7b9522c9d2a";

describe("incoming swipes route", () => {
  beforeEach(() => {
    queryMock.mockReset();
    signedProfilePhotoUrlMock.mockReset();
    signedProfilePhotoUrlMock.mockResolvedValue("https://cdn.example.com/liker-main.jpg");
    withSignedPhotoUrlsMock.mockReset();
    withSignedPhotoUrlsMock.mockImplementation(async (photos: any[]) => photos);
  });

  it("returns incoming likes with full profile details", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM swipes s") && sql.includes("WHERE s.target_id = $1")) {
        return {
          rows: [{
            id: liker,
            name: "Dhanush",
            age: 21,
            bio: "Tester",
            profession: "Chef",
            gender: "Male",
            height: 171,
            interests: ["Travel"],
            is_verified: false,
            looking_for: "Dating",
            direction: "like",
            created_at: new Date("2026-05-28T04:40:00.000Z"),
            venue_id: venueId
          }],
          rowCount: 1
        };
      }
      if (sql.includes("FROM profile_prompts")) {
        return { rows: [], rowCount: 0 };
      }
      if (sql.includes("FROM profile_photos")) {
        return {
          rows: [{
            id: "photo-1",
            storage_key: "users/liker/main.jpg",
            cdn_url: "https://cdn.example.com/liker-main.jpg",
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
      url: "/swipes/incoming",
      headers: authHeader(me)
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({
      swipes: [{
        profile: expect.objectContaining({
          id: liker,
          name: "Dhanush",
          age: 21,
          profession: "Chef",
          lookingFor: "Dating",
          photos: [{ id: "photo-1", storageKey: "users/liker/main.jpg", cdnUrl: "https://cdn.example.com/liker-main.jpg", position: 0 }],
          prompts: []
        }),
        direction: "like",
        createdAt: "2026-05-28T04:40:00.000Z",
        venueId
      }]
    });
    await app.close();
  });

  it("returns empty list when there are no pending incoming likes", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM swipes s") && sql.includes("WHERE s.target_id = $1")) {
        return { rows: [], rowCount: 0 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "GET",
      url: "/swipes/incoming",
      headers: authHeader(me)
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ swipes: [] });
    await app.close();
  });
});
