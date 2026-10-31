import { AuthContext } from "../utils/auth.js";
import { env } from "../config/env.js";
import { query } from "../db/pool.js";
import type { FastifyBaseLogger } from "fastify";

type RealtimeConnection = {
  readyState: number;
  send(data: string): void;
  close(code?: number, reason?: string): void;
  on(event: "close" | "error", listener: () => void): void;
};

export type RealtimePayload = {
  type: string;
  [key: string]: unknown;
};

const openState = 1;
const connectionsByUser = new Map<string, Set<RealtimeConnection>>();
const offlineCheckoutTimers = new Map<string, NodeJS.Timeout>();
export const OFFLINE_CHECKOUT_GRACE_MS = env.offlineCheckoutGraceMinutes * 60 * 1000;
let realtimeLogger: FastifyBaseLogger | undefined;

export function configureRealtimeLogger(logger: FastifyBaseLogger): void {
  realtimeLogger = logger;
}

function connectionKey(userId: string): string {
  return userId.toLowerCase();
}

let autoCheckoutHandler: (userId: string) => Promise<void> = async (userId: string) => {
  await query(
    `
      UPDATE checkins
      SET checked_out_at = now()
      WHERE user_id = $1
        AND checked_out_at IS NULL
    `,
    [userId]
  );
};

export function registerRealtimeConnection(
  auth: AuthContext,
  connection: RealtimeConnection
): void {
  const userId = connectionKey(auth.userId);
  cancelOfflineCheckout(userId);
  pruneClosedConnections(userId);
  const connections = connectionsByUser.get(userId) ?? new Set<RealtimeConnection>();
  connections.add(connection);
  connectionsByUser.set(userId, connections);
  realtimeLogger?.info(
    {
      trace: "realtime.connected",
      userId,
      connectionCount: connections.size
    },
    "[SwipeTrace] Realtime client connected"
  );

  connection.on("close", () => removeConnection(userId, connection));
  connection.on("error", () => removeConnection(userId, connection));

  sendPayload(connection, {
    type: "connection.ready",
    userId
  });

  // Send initial presence snapshot to the newly connected client.
  sendPayload(connection, {
    type: "presence.snapshot",
    userIds: onlineUserIds()
  });

  broadcastPresenceUpdate(userId, true);
}

export function broadcastToUser(userId: string, payload: RealtimePayload): number {
  const normalizedUserId = connectionKey(userId);
  const connections = connectionsByUser.get(normalizedUserId);
  if (!connections) {
    realtimeLogger?.warn(
      {
        trace: "realtime.broadcast",
        targetUserId: normalizedUserId,
        eventType: payload.type,
        connectionCount: 0
      },
      "[SwipeTrace] No realtime connection for target"
    );
    return 0;
  }

  let deliveredCount = 0;
  for (const connection of connections) {
    if (sendPayload(connection, payload)) {
      deliveredCount += 1;
    }
  }
  realtimeLogger?.info(
    {
      trace: "realtime.broadcast",
      targetUserId: normalizedUserId,
      eventType: payload.type,
      connectionCount: connections.size,
      deliveredCount
    },
    "[SwipeTrace] Realtime broadcast completed"
  );
  return deliveredCount;
}

export function disconnectRealtimeUser(userId: string): void {
  const normalizedUserId = connectionKey(userId);
  const connections = connectionsByUser.get(normalizedUserId);
  if (!connections || connections.size === 0) { return; }

  for (const connection of Array.from(connections)) {
    try {
      connection.close(1000, "Signed out");
    } catch {
      // Ignore close errors; removeConnection handles cleanup via close/error events.
    }
    removeConnection(normalizedUserId, connection);
  }
}

function sendPayload(connection: RealtimeConnection, payload: RealtimePayload): boolean {
  if (connection.readyState !== openState) { return false; }
  connection.send(JSON.stringify(payload));
  return true;
}

function removeConnection(userId: string, connection: RealtimeConnection): void {
  const connections = connectionsByUser.get(userId);
  if (!connections) { return; }

  connections.delete(connection);
  realtimeLogger?.info(
    {
      trace: "realtime.disconnected",
      userId,
      remainingConnections: connections.size
    },
    "[SwipeTrace] Realtime client disconnected"
  );
  if (connections.size === 0) {
    connectionsByUser.delete(userId);
    broadcastPresenceUpdate(userId, false);
    scheduleOfflineCheckout(userId);
  }
}

function isUserOnline(userId: string): boolean {
  pruneClosedConnections(userId);
  const connections = connectionsByUser.get(userId);
  return Boolean(connections && connections.size > 0);
}

function onlineUserIds(): string[] {
  for (const userId of Array.from(connectionsByUser.keys())) {
    pruneClosedConnections(userId);
  }
  return Array.from(connectionsByUser.keys());
}

function pruneClosedConnections(userId: string): void {
  const connections = connectionsByUser.get(userId);
  if (!connections) { return; }

  for (const connection of Array.from(connections)) {
    if (connection.readyState !== openState) {
      connections.delete(connection);
    }
  }

  if (connections.size === 0) {
    connectionsByUser.delete(userId);
  }
}

function broadcastPresenceUpdate(userId: string, online: boolean): void {
  for (const [connectedUserId] of connectionsByUser) {
    broadcastToUser(connectedUserId, {
      type: "presence.update",
      userId,
      online
    });
  }
}

function scheduleOfflineCheckout(userId: string): void {
  cancelOfflineCheckout(userId);

  const timer = setTimeout(async () => {
    offlineCheckoutTimers.delete(userId);
    if (isUserOnline(userId)) { return; }

    try {
      await autoCheckoutHandler(userId);
    } catch {
      // Ignore checkout errors; user can still manually checkout/reconnect.
    }
  }, OFFLINE_CHECKOUT_GRACE_MS);
  timer.unref();
  offlineCheckoutTimers.set(userId, timer);
}

function cancelOfflineCheckout(userId: string): void {
  const timer = offlineCheckoutTimers.get(userId);
  if (!timer) { return; }
  clearTimeout(timer);
  offlineCheckoutTimers.delete(userId);
}

export function __setAutoCheckoutHandlerForTests(
  handler: ((userId: string) => Promise<void>) | undefined
): void {
  autoCheckoutHandler = handler ?? (async (userId: string) => {
    await query(
      `
        UPDATE checkins
        SET checked_out_at = now()
        WHERE user_id = $1
          AND checked_out_at IS NULL
      `,
      [userId]
    );
  });
}

export function __resetChatHubStateForTests(): void {
  for (const timer of offlineCheckoutTimers.values()) {
    clearTimeout(timer);
  }
  offlineCheckoutTimers.clear();
  connectionsByUser.clear();
  __setAutoCheckoutHandlerForTests(undefined);
}
