import { beforeEach, vi } from "vitest";
import { signAccessToken } from "../../src/utils/auth.js";

const { queryMock } = vi.hoisted(() => ({
  queryMock: vi.fn()
}));

const { broadcastToUserMock } = vi.hoisted(() => ({
  broadcastToUserMock: vi.fn()
}));

const { signedProfilePhotoUrlMock } = vi.hoisted(() => ({
  signedProfilePhotoUrlMock: vi.fn()
}));

vi.mock("../../src/db/pool.js", () => ({
  query: queryMock,
  withTransaction: vi.fn(),
  closePool: vi.fn()
}));

vi.mock("../../src/realtime/chatHub.js", () => ({
  configureRealtimeLogger: vi.fn(),
  broadcastToUser: broadcastToUserMock
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
const other = "4f34e495-a51f-498c-86a9-5c2cba3a9e5a";
const matchId = "e8317929-5c39-4f1e-a1eb-6e5b2a8c3038";

describe("matches routes", () => {
  beforeEach(() => {
    queryMock.mockReset();
    broadcastToUserMock.mockReset();
    signedProfilePhotoUrlMock.mockReset();
    signedProfilePhotoUrlMock.mockResolvedValue("https://cdn.example.com/photo.jpg");
    withSignedPhotoUrlsMock.mockReset();
    withSignedPhotoUrlsMock.mockImplementation(async (photos: any[]) => photos);
  });

  it("returns matches list", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("SELECT m.id AS match_id")) {
        return {
          rows: [{
            match_id: matchId,
            venue_id: "abf264f1-6cea-4cb9-bdaf-a7b9522c9d2a",
            venue_name: "10 Downing Street",
            matched_at: new Date("2026-05-25T10:00:00.000Z"),
            updated_at: new Date("2026-05-25T10:05:00.000Z"),
            deleted_at: null,
            id: other,
            name: "Dhanush",
            age: 21,
            bio: "Tester",
            profession: "Chef",
            gender: "Male",
            height: 171,
            interests: ["Travel"],
            is_verified: false,
            looking_for: "Friends",
            last_message: "Hi",
            last_message_at: new Date("2026-05-25T10:05:00.000Z"),
            unread_count: "2"
          }],
          rowCount: 1
        };
      }
      if (sql.includes("FROM profile_prompts")) {
        return { rows: [], rowCount: 0 };
      }
      if (sql.includes("FROM profile_photos")) {
        return { rows: [], rowCount: 0 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({ method: "GET", url: "/matches", headers: authHeader(me) });

    expect(response.statusCode).toBe(200);
    const body = response.json();
    expect(body.matches).toHaveLength(1);
    expect(body.matches[0].id).toBe(matchId);
    expect(body.matches[0].unreadCount).toBe(2);
    expect(body.matches[0].lastMessage).toBe("Hi");
    expect(body.matches[0].venueName).toBe("10 Downing Street");
    expect(body.matches[0].updatedAt).toBe("2026-05-25T10:05:00.000Z");
    expect(body.matches[0].deletedAt).toBeNull();
    await app.close();
  });

  it("passes matches cursor and pagination params to the query", async () => {
    queryMock.mockImplementation(async (sql: string, params: unknown[]) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("SELECT m.id AS match_id")) {
        expect(params[1]).toEqual(new Date(1_748_512_000_000));
        expect(params[2]).toBe(true);
        expect(params[3]).toBe(10);
        expect(params[4]).toBe(20);
        return { rows: [], rowCount: 0 };
      }
      if (sql.includes("SELECT count(*)::text AS count")) {
        expect(params[1]).toEqual(new Date(1_748_512_000_000));
        expect(params[2]).toBe(true);
        return { rows: [{ count: "42" }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "GET",
      url: "/matches?updatedSince=1748512000000&limit=10&page=3",
      headers: authHeader(me)
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ matches: [], total: 42, page: 3, limit: 10 });
    await app.close();
  });

  it("returns 404 for messages when user cannot access match", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM matches m")) {
        return { rows: [], rowCount: 0 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "GET",
      url: `/matches/${matchId}/messages`,
      headers: authHeader(me)
    });

    expect(response.statusCode).toBe(404);
    expect(response.json()).toEqual({ error: "Match not found" });
    await app.close();
  });

  it("returns messages with pagination params", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM matches m")) {
        return { rows: [{ "?column?": 1 }], rowCount: 1 };
      }
      if (sql.includes("WITH selected_messages AS")) {
        return {
          rows: [
            {
              id: "m1",
              match_id: matchId,
              sender_id: me,
              body: "hello",
              is_read: true,
              created_at: new Date("2026-05-25T10:00:00.000Z"),
              updated_at: new Date("2026-05-25T10:00:00.000Z"),
              deleted_at: null
            }
          ],
          rowCount: 1
        };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "GET",
      url: `/matches/${matchId}/messages?limit=10&before=2026-05-25T10:10:00.000Z`,
      headers: authHeader(me)
    });

    expect(response.statusCode).toBe(200);
    expect(response.json().messages).toHaveLength(1);
    expect(response.json().messages[0].isFromMe).toBe(true);
    expect(response.json().messages[0].deletedAt).toBeNull();
    await app.close();
  });

  it("passes messages since cursor and page params to the query", async () => {
    queryMock.mockImplementation(async (sql: string, params: unknown[]) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM matches m")) {
        return { rows: [{ "?column?": 1 }], rowCount: 1 };
      }
      if (sql.includes("WITH selected_messages AS")) {
        expect(params).toEqual([
          matchId,
          new Date(1_748_512_000_000),
          null,
          25,
          25
        ]);
        return { rows: [], rowCount: 0 };
      }
      if (sql.includes("SELECT count(*)::text AS count")) {
        expect(params).toEqual([matchId, new Date(1_748_512_000_000), null]);
        return { rows: [{ count: "52" }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "GET",
      url: `/matches/${matchId}/messages?since=1748512000000&limit=25&page=2`,
      headers: authHeader(me)
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ messages: [], total: 52, page: 2, limit: 25 });
    await app.close();
  });

  it("rejects send message when body is empty", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM matches m")) {
        return { rows: [{ "?column?": 1 }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: `/matches/${matchId}/messages`,
      headers: authHeader(me),
      payload: { body: "   " }
    });

    expect(response.statusCode).toBe(400);
    expect(response.json()).toEqual({ error: "body is required" });
    await app.close();
  });

  it("sends message and broadcasts to recipient", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM matches m")) {
        return { rows: [{ "?column?": 1 }], rowCount: 1 };
      }
      if (sql.includes("INSERT INTO messages")) {
        return {
          rows: [{
            id: "msg1",
            match_id: matchId,
            sender_id: me,
            body: "Hey",
            is_read: false,
            created_at: new Date("2026-05-25T10:00:00.000Z"),
            updated_at: new Date("2026-05-25T10:00:00.000Z"),
            deleted_at: null
          }],
          rowCount: 1
        };
      }
      if (sql.includes("SELECT user_a_id, user_b_id")) {
        return { rows: [{ user_a_id: me, user_b_id: other }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: `/matches/${matchId}/messages`,
      headers: authHeader(me),
      payload: { body: "Hey" }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json().message.body).toBe("Hey");
    expect(broadcastToUserMock).toHaveBeenCalledTimes(1);
    expect(broadcastToUserMock).toHaveBeenCalledWith(
      other,
      expect.objectContaining({ type: "message.created" })
    );
    await app.close();
  });

  it("marks messages read without upToMessageId and broadcasts", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM matches m")) {
        return { rows: [{ "?column?": 1 }], rowCount: 1 };
      }
      if (sql.includes("UPDATE messages SET is_read = true WHERE match_id = $1 AND sender_id != $2")) {
        return { rows: [], rowCount: 2 };
      }
      if (sql.includes("SELECT user_a_id, user_b_id")) {
        return { rows: [{ user_a_id: me, user_b_id: other }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "PUT",
      url: `/matches/${matchId}/messages/read`,
      headers: authHeader(me),
      payload: {}
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ ok: true });
    expect(broadcastToUserMock).toHaveBeenCalledWith(
      other,
      expect.objectContaining({ type: "messages.read", upToMessageId: null })
    );
    await app.close();
  });

  it("marks messages read with upToMessageId and broadcasts", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM matches m")) {
        return { rows: [{ "?column?": 1 }], rowCount: 1 };
      }
      if (sql.includes("UPDATE messages")) {
        return { rows: [], rowCount: 1 };
      }
      if (sql.includes("SELECT user_a_id, user_b_id")) {
        return { rows: [{ user_a_id: me, user_b_id: other }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "PUT",
      url: `/matches/${matchId}/messages/read`,
      headers: authHeader(me),
      payload: { upToMessageId: "m1" }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ ok: true });
    expect(broadcastToUserMock).toHaveBeenCalledWith(
      other,
      expect.objectContaining({ type: "messages.read", upToMessageId: "m1" })
    );
    await app.close();
  });

  it("deletes match successfully", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("SELECT user_a_id, user_b_id FROM matches")) {
        return { rows: [{ user_a_id: me, user_b_id: other }], rowCount: 1 };
      }
      if (sql.includes("UPDATE matches")) {
        return { rows: [], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "DELETE",
      url: `/matches/${matchId}`,
      headers: authHeader(me)
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ ok: true });
    await app.close();
  });

  it("returns 404 when deleting unknown match", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("SELECT user_a_id, user_b_id FROM matches")) {
        return { rows: [{ user_a_id: me, user_b_id: other }], rowCount: 1 };
      }
      if (sql.includes("UPDATE matches")) {
        return { rows: [], rowCount: 0 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "DELETE",
      url: `/matches/${matchId}`,
      headers: authHeader(me)
    });

    expect(response.statusCode).toBe(404);
    expect(response.json()).toEqual({ error: "Match not found" });
    await app.close();
  });
});
