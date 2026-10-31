import { beforeEach, vi } from "vitest";
import { signAccessToken } from "../../src/utils/auth.js";

const { queryMock, withTransactionMock } = vi.hoisted(() => ({
  queryMock: vi.fn(),
  withTransactionMock: vi.fn()
}));
const { broadcastToUserMock } = vi.hoisted(() => ({
  broadcastToUserMock: vi.fn()
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

import { buildApp } from "../../src/app.js";

function authHeader(userId: string): Record<string, string> {
  const token = signAccessToken({ userId, phone: "+911234567890" });
  return { authorization: `Bearer ${token}` };
}

describe("venues + safety routes", () => {
  beforeEach(() => {
    queryMock.mockReset();
    withTransactionMock.mockReset();
    broadcastToUserMock.mockReset();

    withTransactionMock.mockImplementation(async (cb: (client: { query: typeof queryMock }) => Promise<void>) => {
      await cb({ query: queryMock });
    });
  });

  it("rejects check-in without coordinates", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/venues/abf264f1-6cea-4cb9-bdaf-a7b9522c9d2a/checkin",
      headers: authHeader("505f7fc3-2d06-4b96-aa90-6380f511ffde"),
      payload: {}
    });

    expect(response.statusCode).toBe(400);
    expect(response.json()).toEqual({ error: "Current location is required to check in" });
    await app.close();
  });

  it("rejects check-in outside allowed radius", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("SELECT id, name, latitude, longitude, checkin_radius_meters")) {
        return {
          rows: [{
            id: "abf264f1-6cea-4cb9-bdaf-a7b9522c9d2a",
            name: "10 Downing Street",
            latitude: 17.4349,
            longitude: 78.3996,
            checkin_radius_meters: 200
          }],
          rowCount: 1
        };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/venues/abf264f1-6cea-4cb9-bdaf-a7b9522c9d2a/checkin",
      headers: authHeader("505f7fc3-2d06-4b96-aa90-6380f511ffde"),
      payload: {
        latitude: 17.50,
        longitude: 78.50
      }
    });

    expect(response.statusCode).toBe(403);
    expect(response.json()).toEqual({ error: "You need to be at 10 Downing Street to check in." });
    await app.close();
  });

  it("returns hidden users list from safety endpoint", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("SELECT hidden.user_id")) {
        return {
          rows: [
            { user_id: "4f34e495-a51f-498c-86a9-5c2cba3a9e5a" },
            { user_id: "505f7fc3-2d06-4b96-aa90-6380f511ffde" }
          ],
          rowCount: 2
        };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "GET",
      url: "/safety/hidden-users",
      headers: authHeader("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({
      userIds: [
        "4f34e495-a51f-498c-86a9-5c2cba3a9e5a",
        "505f7fc3-2d06-4b96-aa90-6380f511ffde"
      ]
    });
    await app.close();
  });

  it("returns empty hidden users list when none exist", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("SELECT hidden.user_id")) {
        return { rows: [], rowCount: 0 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "GET",
      url: "/safety/hidden-users",
      headers: authHeader("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ userIds: [] });
    await app.close();
  });

  it("reports spam and broadcasts match.unmatched to both users", async () => {
    const reporter = "505f7fc3-2d06-4b96-aa90-6380f511ffde";
    const reported = "ceb38698-5a7e-47fc-9cf8-fcd1234c1c3c";
    const matchId = "22c8c450-7555-4962-b661-40423d4c29df";

    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("SELECT 1") && sql.includes("FROM matches") && sql.includes("WHERE id = $1")) {
        return { rows: [{ "?column?": 1 }], rowCount: 1 };
      }
      if (sql.includes("SELECT id") && sql.includes("FROM matches") && sql.includes("unmatched_at IS NULL")) {
        return { rows: [{ id: matchId }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/reports",
      headers: authHeader(reporter),
      payload: {
        reportedUserId: reported,
        matchId,
        category: "spam",
        reason: "Scam links",
        details: "Reported from chat."
      }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ ok: true });
    expect(broadcastToUserMock).toHaveBeenCalledWith(
      reporter,
      expect.objectContaining({ type: "match.unmatched", matchId })
    );
    expect(broadcastToUserMock).toHaveBeenCalledWith(
      reported,
      expect.objectContaining({ type: "match.unmatched", matchId })
    );
    expect(broadcastToUserMock).toHaveBeenCalledWith(
      reporter,
      expect.objectContaining({ type: "safety.hidden_users_updated" })
    );
    expect(broadcastToUserMock).toHaveBeenCalledWith(
      reported,
      expect.objectContaining({ type: "safety.hidden_users_updated" })
    );
    await app.close();
  });

  it("blocks user, unmatches active matches, and broadcasts both event types", async () => {
    const blocker = "505f7fc3-2d06-4b96-aa90-6380f511ffde";
    const blocked = "ceb38698-5a7e-47fc-9cf8-fcd1234c1c3c";
    const activeMatchId = "22c8c450-7555-4962-b661-40423d4c29df";

    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("SELECT id") && sql.includes("FROM matches") && sql.includes("unmatched_at IS NULL")) {
        return { rows: [{ id: activeMatchId }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/blocks",
      headers: authHeader(blocker),
      payload: {
        blockedUserId: blocked
      }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ ok: true });
    expect(broadcastToUserMock).toHaveBeenCalledWith(
      blocker,
      expect.objectContaining({ type: "match.unmatched", matchId: activeMatchId })
    );
    expect(broadcastToUserMock).toHaveBeenCalledWith(
      blocked,
      expect.objectContaining({ type: "match.unmatched", matchId: activeMatchId })
    );
    expect(broadcastToUserMock).toHaveBeenCalledWith(
      blocker,
      expect.objectContaining({ type: "safety.hidden_users_updated" })
    );
    expect(broadcastToUserMock).toHaveBeenCalledWith(
      blocked,
      expect.objectContaining({ type: "safety.hidden_users_updated" })
    );
    await app.close();
  });
});
