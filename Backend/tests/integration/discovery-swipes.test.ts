import { beforeEach, vi } from "vitest";
import { signAccessToken } from "../../src/utils/auth.js";

const { queryMock, withTransactionMock } = vi.hoisted(() => ({
  queryMock: vi.fn(),
  withTransactionMock: vi.fn()
}));

const { broadcastToUserMock } = vi.hoisted(() => ({
  broadcastToUserMock: vi.fn()
}));

const { signedProfilePhotoUrlMock, withSignedPhotoUrlsMock } = vi.hoisted(() => ({
  signedProfilePhotoUrlMock: vi.fn(),
  withSignedPhotoUrlsMock: vi.fn()
}));

vi.mock("../../src/db/pool.js", () => ({
  query: queryMock,
  withTransaction: withTransactionMock,
  closePool: vi.fn()
}));

vi.mock("../../src/realtime/chatHub.js", () => ({
  configureRealtimeLogger: vi.fn(),
  broadcastToUser: broadcastToUserMock
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

const actorId = "505f7fc3-2d06-4b96-aa90-6380f511ffde";
const targetId = "4f34e495-a51f-498c-86a9-5c2cba3a9e5a";
const venueId = "abf264f1-6cea-4cb9-bdaf-a7b9522c9d2a";
const matchId = "e8317929-5c39-4f1e-a1eb-6e5b2a8c3038";

describe("discovery swipes routes", () => {
  beforeEach(() => {
    queryMock.mockReset();
    withTransactionMock.mockReset();
    withTransactionMock.mockImplementation(
      async (callback: (client: { query: typeof queryMock }) => Promise<unknown>) => callback({ query: queryMock })
    );
    broadcastToUserMock.mockReset();
    signedProfilePhotoUrlMock.mockReset();
    signedProfilePhotoUrlMock.mockResolvedValue("https://cdn.example.com/actor-main.jpg");
    withSignedPhotoUrlsMock.mockReset();
    withSignedPhotoUrlsMock.mockImplementation(async (photos) => photos);
  });

  it("returns full venue discovery profiles and excludes existing matches", async () => {
    withSignedPhotoUrlsMock.mockImplementation(async (photos) => photos.map((photo: {
      cdn_url: string | null;
      position: number;
    }) => ({
      ...photo,
      cdn_url: `https://cdn.example.com/target-${photo.position}.jpg`
    })));
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("SELECT pref_age_min")) {
        return {
          rows: [{
            pref_age_min: 18,
            pref_age_max: 60,
            pref_genders: [],
            pref_height_min: 100,
            pref_height_max: 250,
            pref_verified_only: false
          }],
          rowCount: 1
        };
      }
      if (sql.includes("JOIN checkins c")) {
        return {
          rows: [{
            id: targetId,
            name: "Dhanush",
            age: 21,
            bio: "Tester",
            profession: "Chef",
            gender: "Male",
            height: 171,
            interests: ["Travel"],
            is_verified: false,
            is_ghost_mode: false,
            looking_for: "Long-term relationship",
            has_super_liked_me: true
          }],
          rowCount: 1
        };
      }
      if (sql.includes("FROM profile_prompts")) {
        return {
          rows: [{
            id: "9faebdc6-a641-4ba4-9d84-b7a6b3bb0e89",
            question: "My perfect weekend",
            answer: "Trying a new restaurant",
            position: 0
          }],
          rowCount: 1
        };
      }
      if (sql.includes("FROM profile_photos")) {
        return {
          rows: [
            {
              id: "7bb1e278-55e8-431d-a5f7-12fc1fdb9387",
              storage_key: "users/dhanush/main.jpg",
              cdn_url: "https://legacy.cdn/target-main.jpg",
              position: 0
            },
            {
              id: "6a5ae934-514a-4f6c-ae91-038932870fbf",
              storage_key: "users/dhanush/second.jpg",
              cdn_url: "https://legacy.cdn/target-second.jpg",
              position: 1
            }
          ],
          rowCount: 2
        };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "GET",
      url: `/venues/${venueId}/discover`,
      headers: authHeader(actorId)
    });

    expect(response.statusCode).toBe(200);
    expect(response.json().profiles[0]).toEqual(expect.objectContaining({
      id: targetId,
      lookingFor: "Long-term relationship",
      hasSuperLikedMe: true,
      prompts: [
        expect.objectContaining({
          question: "My perfect weekend",
          answer: "Trying a new restaurant"
        })
      ],
      photos: [
        expect.objectContaining({
          cdnUrl: "https://cdn.example.com/target-0.jpg",
          position: 0
        }),
        expect.objectContaining({
          cdnUrl: "https://cdn.example.com/target-1.jpg",
          position: 1
        })
      ]
    }));
    const discoverSQL = queryMock.mock.calls
      .map(([sql]) => sql as string)
      .find((sql) => sql.includes("JOIN checkins c"));
    expect(discoverSQL).toContain("SELECT 1 FROM matches m");
    expect(discoverSQL).toContain("u.is_ghost_mode = false");
    expect(discoverSQL).not.toContain("latest.unmatched_at IS NOT NULL");
    await app.close();
  });

  it("broadcasts swipe.received for like", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM users u") && sql.includes("WHERE u.id = $1") && sql.includes("NOT EXISTS")) {
        return { rows: [{ 1: 1 }], rowCount: 1 };
      }
      if (sql.includes("SELECT * FROM record_swipe")) {
        return { rows: [{ is_match: false, match_id: null }], rowCount: 1 };
      }
      if (sql.includes("LEFT JOIN profile_photos pp ON pp.user_id = u.id AND pp.position = 0")) {
        return {
          rows: [{
            id: actorId,
            name: "SaiPavan",
            age: 28,
            bio: "Nthing",
            profession: "Software engineer",
            gender: "Female",
            height: 168,
            interests: ["Travel"],
            is_verified: false,
            looking_for: "Something Casual",
            photo_url: "https://old.example.com/avatar.jpg",
            photo_storage_key: "users/actor/main.jpg"
          }],
          rowCount: 1
        };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/swipes",
      headers: authHeader(actorId),
      payload: { targetUserId: targetId, venueId, direction: "like" }
    });

    expect(response.statusCode).toBe(200);
    expect(broadcastToUserMock).toHaveBeenCalledTimes(1);
    expect(broadcastToUserMock).toHaveBeenCalledWith(
      targetId,
      expect.objectContaining({
        type: "swipe.received",
        direction: "like",
        isMatch: false,
        matchId: null,
        venueId,
        profile: expect.objectContaining({
          id: actorId,
          name: "SaiPavan",
          photoUrl: "https://cdn.example.com/actor-main.jpg",
          lookingFor: "Something Casual"
        })
      })
    );
    await app.close();
  });

  it("does not broadcast swipe.received for nope", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM users u") && sql.includes("WHERE u.id = $1") && sql.includes("NOT EXISTS")) {
        return { rows: [{ 1: 1 }], rowCount: 1 };
      }
      if (sql.includes("SELECT * FROM record_swipe")) {
        return { rows: [{ is_match: false, match_id: null }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/swipes",
      headers: authHeader(actorId),
      payload: { targetUserId: targetId, venueId, direction: "nope" }
    });

    expect(response.statusCode).toBe(200);
    expect(broadcastToUserMock).not.toHaveBeenCalled();
    await app.close();
  });

  it("broadcasts swipe.received with matchId when swipe creates match", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM users u") && sql.includes("WHERE u.id = $1") && sql.includes("NOT EXISTS")) {
        return { rows: [{ 1: 1 }], rowCount: 1 };
      }
      if (sql.includes("SELECT * FROM record_swipe")) {
        return { rows: [{ is_match: true, match_id: matchId }], rowCount: 1 };
      }
      if (sql.includes("LEFT JOIN profile_photos pp ON pp.user_id = u.id AND pp.position = 0")) {
        return {
          rows: [{
            id: actorId,
            name: "SaiPavan",
            age: 28,
            bio: "Nthing",
            profession: "Software engineer",
            gender: "Female",
            height: 168,
            interests: ["Travel"],
            is_verified: false,
            photo_url: null,
            photo_storage_key: null
          }],
          rowCount: 1
        };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/swipes",
      headers: authHeader(actorId),
      payload: { targetUserId: targetId, venueId, direction: "superlike" }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ isMatch: true, matchId });
    expect(broadcastToUserMock).toHaveBeenCalledWith(
      targetId,
      expect.objectContaining({
        type: "swipe.received",
        direction: "superlike",
        isMatch: true,
        matchId
      })
    );
    await app.close();
  });

  it("treats a like back as acceptance of an incoming invite", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM users u") && sql.includes("WHERE u.id = $1") && sql.includes("NOT EXISTS")) {
        return { rows: [{ 1: 1 }], rowCount: 1 };
      }
      if (sql.includes("SELECT id, sender_id, receiver_id, venue_id") && sql.includes("sender_id = $2")) {
        return {
          rows: [{
            id: "f8317929-5c39-4f1e-a1eb-6e5b2a8c3038",
            sender_id: targetId,
            receiver_id: actorId,
            venue_id: venueId
          }],
          rowCount: 1
        };
      }
      if (sql.includes("SELECT id") && sql.includes("FROM matches")) {
        return { rows: [], rowCount: 0 };
      }
      if (sql.includes("INSERT INTO matches")) {
        return { rows: [{ id: matchId }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/swipes",
      headers: authHeader(actorId),
      payload: { targetUserId: targetId, venueId, direction: "like" }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ isMatch: true, matchId });
    expect(queryMock.mock.calls.filter(([sql]) => (sql as string).includes("SELECT * FROM record_swipe"))).toHaveLength(0);
    expect(queryMock.mock.calls.filter(([sql]) => (sql as string).includes("INSERT INTO matches"))).toHaveLength(1);
    expect(queryMock).toHaveBeenCalledWith(
      expect.stringContaining("SET status = CASE WHEN id = $1 THEN $3 ELSE 'accepted' END"),
      ["f8317929-5c39-4f1e-a1eb-6e5b2a8c3038", matchId, "accepted_by_like", targetId, actorId]
    );
    expect(broadcastToUserMock).toHaveBeenCalledWith(
      targetId,
      expect.objectContaining({
        type: "invite.accepted",
        matchId,
        status: "accepted_by_like"
      })
    );
    await app.close();
  });
});
