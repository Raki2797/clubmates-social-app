import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  __resetChatHubStateForTests,
  __setAutoCheckoutHandlerForTests,
  OFFLINE_CHECKOUT_GRACE_MS,
  broadcastToUser,
  disconnectRealtimeUser,
  registerRealtimeConnection
} from "../../src/realtime/chatHub.js";

type MockConnection = {
  readyState: number;
  sent: string[];
  closed: Array<{ code?: number; reason?: string }>;
  send: (data: string) => void;
  close: (code?: number, reason?: string) => void;
  on: (event: "close" | "error", listener: () => void) => void;
  trigger: (event: "close" | "error") => void;
};

function createConnection(readyState = 1): MockConnection {
  const listeners: Partial<Record<"close" | "error", Array<() => void>>> = {};
  const conn: MockConnection = {
    readyState,
    sent: [],
    closed: [],
    send: vi.fn((data: string) => {
      conn.sent.push(data);
    }),
    close: vi.fn((code?: number, reason?: string) => {
      conn.closed.push({ code, reason });
      conn.trigger("close");
    }),
    on: vi.fn((event, listener) => {
      const current = listeners[event] ?? [];
      listeners[event] = [...current, listener];
    }),
    trigger: (event) => {
      for (const listener of listeners[event] ?? []) {
        listener();
      }
    }
  };
  return conn;
}

describe("chatHub disconnectRealtimeUser", () => {
  beforeEach(() => {
    __resetChatHubStateForTests();
  });

  afterEach(() => {
    vi.useRealTimers();
    __resetChatHubStateForTests();
  });

  it("auto-checks out after offline grace period", async () => {
    vi.useFakeTimers();

    const userId = "505f7fc3-2d06-4b96-aa90-6380f511ffde";
    const conn = createConnection();
    const checkoutSpy = vi.fn(async () => {});
    __setAutoCheckoutHandlerForTests(checkoutSpy);

    registerRealtimeConnection({ userId, phone: "+911111111111" }, conn);
    conn.trigger("close");

    await vi.advanceTimersByTimeAsync(OFFLINE_CHECKOUT_GRACE_MS - 1);
    expect(checkoutSpy).not.toHaveBeenCalled();

    await vi.advanceTimersByTimeAsync(1);
    expect(checkoutSpy).toHaveBeenCalledWith(userId);
    expect(checkoutSpy).toHaveBeenCalledTimes(1);

  });

  it("cancels pending auto-checkout when user reconnects before grace period", async () => {
    vi.useFakeTimers();

    const userId = "4f34e495-a51f-498c-86a9-5c2cba3a9e5a";
    const first = createConnection();
    const second = createConnection();
    const checkoutSpy = vi.fn(async () => {});
    __setAutoCheckoutHandlerForTests(checkoutSpy);

    registerRealtimeConnection({ userId, phone: "+912222222222" }, first);
    first.trigger("close");
    registerRealtimeConnection({ userId, phone: "+912222222222" }, second);

    await vi.advanceTimersByTimeAsync(OFFLINE_CHECKOUT_GRACE_MS);
    expect(checkoutSpy).not.toHaveBeenCalled();

  });

  it("broadcasts an online presence update when a user opens another realtime connection", () => {
    const userId = "4f34e495-a51f-498c-86a9-5c2cba3a9e5a";
    const first = createConnection();
    const second = createConnection();

    registerRealtimeConnection({ userId, phone: "+912222222222" }, first);
    registerRealtimeConnection({ userId, phone: "+912222222222" }, second);

    const firstPayloads = first.sent.map((raw) => JSON.parse(raw) as { type: string; userId?: string; online?: boolean });
    const onlineUpdates = firstPayloads.filter((payload) =>
      payload.type === "presence.update"
        && payload.userId === userId
        && payload.online === true
    );

    expect(onlineUpdates).toHaveLength(2);
  });

  it("prunes stale connections from presence snapshots before announcing online users", () => {
    const staleUserId = "505f7fc3-2d06-4b96-aa90-6380f511ffde";
    const activeUserId = "4f34e495-a51f-498c-86a9-5c2cba3a9e5a";
    const stale = createConnection();
    const active = createConnection();

    registerRealtimeConnection({ userId: staleUserId, phone: "+911111111111" }, stale);
    stale.readyState = 3;
    registerRealtimeConnection({ userId: activeUserId, phone: "+912222222222" }, active);

    const activePayloads = active.sent.map((raw) => JSON.parse(raw) as { type: string; userIds?: string[] });
    const snapshot = activePayloads.find((payload) => payload.type === "presence.snapshot");

    expect(snapshot?.userIds).toEqual([activeUserId]);
  });

  it("closes all realtime connections for a user", () => {
    const userId = "505f7fc3-2d06-4b96-aa90-6380f511ffde";
    const first = createConnection();
    const second = createConnection();

    registerRealtimeConnection({ userId, phone: "+911111111111" }, first);
    registerRealtimeConnection({ userId, phone: "+911111111111" }, second);

    disconnectRealtimeUser(userId);

    expect(first.close).toHaveBeenCalledWith(1000, "Signed out");
    expect(second.close).toHaveBeenCalledWith(1000, "Signed out");
  });

  it("removes user from broadcast recipients after disconnect", () => {
    const userId = "4f34e495-a51f-498c-86a9-5c2cba3a9e5a";
    const conn = createConnection();

    registerRealtimeConnection({ userId, phone: "+912222222222" }, conn);
    disconnectRealtimeUser(userId);
    broadcastToUser(userId, { type: "message.created", text: "hi" });

    const sentPayloads = conn.sent.map((raw) => JSON.parse(raw) as { type: string });
    expect(sentPayloads.some((payload) => payload.type === "message.created")).toBe(false);
  });

  it("matches UUID connection keys regardless of letter casing", () => {
    const lowercaseUserId = "505f7fc3-2d06-4b96-aa90-6380f511ffde";
    const uppercaseUserId = lowercaseUserId.toUpperCase();
    const conn = createConnection();

    registerRealtimeConnection(
      { userId: lowercaseUserId, phone: "+912222222222" },
      conn
    );

    const deliveredCount = broadcastToUser(uppercaseUserId, {
      type: "swipe.received"
    });

    const sentPayloads = conn.sent.map((raw) => JSON.parse(raw) as { type: string });
    expect(deliveredCount).toBe(1);
    expect(sentPayloads.some((payload) => payload.type === "swipe.received")).toBe(true);
  });

  it("is a no-op for unknown users", () => {
    expect(() => disconnectRealtimeUser("unknown-user")).not.toThrow();
  });
});
