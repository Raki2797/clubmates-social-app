import { beforeEach, vi } from "vitest";

const { queryMock } = vi.hoisted(() => ({
  queryMock: vi.fn()
}));

const { disconnectRealtimeUserMock } = vi.hoisted(() => ({
  disconnectRealtimeUserMock: vi.fn()
}));

vi.mock("../../src/db/pool.js", () => ({
  query: queryMock,
  withTransaction: vi.fn(),
  closePool: vi.fn()
}));

vi.mock("../../src/realtime/chatHub.js", () => ({
  configureRealtimeLogger: vi.fn(),
  registerRealtimeConnection: vi.fn(),
  broadcastToUser: vi.fn(),
  disconnectRealtimeUser: disconnectRealtimeUserMock
}));

import { buildApp } from "../../src/app.js";

describe("auth session presence", () => {
  beforeEach(() => {
    queryMock.mockReset();
    disconnectRealtimeUserMock.mockReset();
  });

  it("disconnects realtime sockets on logout when refresh token owner is found", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT user_id FROM refresh_tokens")) {
        return {
          rows: [{ user_id: "505f7fc3-2d06-4b96-aa90-6380f511ffde" }],
          rowCount: 1
        };
      }
      if (sql.includes("UPDATE refresh_tokens SET revoked_at = now()")) {
        return { rows: [], rowCount: 1 };
      }
      if (sql.includes("UPDATE checkins") && sql.includes("checked_out_at = now()")) {
        return { rows: [], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "DELETE",
      url: "/auth/session",
      payload: { refreshToken: "refresh-token-value" }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ ok: true });
    expect(queryMock).toHaveBeenCalledWith(
      expect.stringContaining("UPDATE checkins"),
      ["505f7fc3-2d06-4b96-aa90-6380f511ffde"]
    );
    expect(disconnectRealtimeUserMock).toHaveBeenCalledWith("505f7fc3-2d06-4b96-aa90-6380f511ffde");
    expect(disconnectRealtimeUserMock).toHaveBeenCalledTimes(1);
    await app.close();
  });

  it("does not disconnect realtime sockets when refresh token is missing", async () => {
    const app = await buildApp();
    const response = await app.inject({
      method: "DELETE",
      url: "/auth/session",
      payload: {}
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ ok: true });
    expect(queryMock).not.toHaveBeenCalledWith(
      expect.stringContaining("SELECT user_id FROM refresh_tokens"),
      expect.anything()
    );
    expect(disconnectRealtimeUserMock).not.toHaveBeenCalled();
    await app.close();
  });

  it("does not disconnect realtime sockets when token owner is not found", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT user_id FROM refresh_tokens")) {
        return { rows: [], rowCount: 0 };
      }
      if (sql.includes("UPDATE refresh_tokens SET revoked_at = now()")) {
        return { rows: [], rowCount: 0 };
      }
      if (sql.includes("UPDATE checkins") && sql.includes("checked_out_at = now()")) {
        return { rows: [], rowCount: 0 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "DELETE",
      url: "/auth/session",
      payload: { refreshToken: "missing-token" }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ ok: true });
    expect(queryMock).not.toHaveBeenCalledWith(
      expect.stringContaining("UPDATE checkins"),
      expect.anything()
    );
    expect(disconnectRealtimeUserMock).not.toHaveBeenCalled();
    await app.close();
  });
});
