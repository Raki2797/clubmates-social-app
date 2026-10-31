import { beforeEach, vi } from "vitest";
import { signAccessToken } from "../../src/utils/auth.js";

const { queryMock, withTransactionMock } = vi.hoisted(() => ({
  queryMock: vi.fn(),
  withTransactionMock: vi.fn()
}));

const { broadcastToUserMock } = vi.hoisted(() => ({
  broadcastToUserMock: vi.fn()
}));

const { signedProfilePhotoUrlMock } = vi.hoisted(() => ({
  signedProfilePhotoUrlMock: vi.fn()
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
  signedProfilePhotoUrl: signedProfilePhotoUrlMock
}));

import { buildApp } from "../../src/app.js";

function authHeader(userId: string): Record<string, string> {
  const token = signAccessToken({ userId, phone: "+911234567890" });
  return { authorization: `Bearer ${token}` };
}

const senderId = "505f7fc3-2d06-4b96-aa90-6380f511ffde";
const receiverId = "4f34e495-a51f-498c-86a9-5c2cba3a9e5a";
const venueId = "abf264f1-6cea-4cb9-bdaf-a7b9522c9d2a";
const inviteId = "f8317929-5c39-4f1e-a1eb-6e5b2a8c3038";
const matchId = "e8317929-5c39-4f1e-a1eb-6e5b2a8c3038";
const walletId = "b1234567-1234-1234-1234-123456789abc";
const coinTxId = "c1234567-1234-1234-1234-123456789abc";
const pkgId = "d1234567-1234-1234-1234-123456789abc";

describe("treat invite routes", () => {
  beforeEach(() => {
    queryMock.mockReset();
    withTransactionMock.mockReset();
    withTransactionMock.mockImplementation(
      async (callback: (client: { query: typeof queryMock }) => Promise<unknown>) => callback({ query: queryMock })
    );
    broadcastToUserMock.mockReset();
    signedProfilePhotoUrlMock.mockReset();
    signedProfilePhotoUrlMock.mockResolvedValue("https://cdn.example.com/sender.jpg");
  });

  it("creates a fixed treat invite and broadcasts it", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("SELECT 1 FROM users u")) {
        return { rows: [{ "?column?": 1 }], rowCount: 1 };
      }
      // Coin: get treat pricing
      if (sql.includes("SELECT sender_cost, receiver_credit FROM treat_pricing")) {
        return { rows: [{ sender_cost: 150, receiver_credit: 120 }], rowCount: 1 };
      }
      // Coin: wallet lazy-create (ON CONFLICT DO NOTHING)
      if (sql.includes("INSERT INTO wallets") && sql.includes("ON CONFLICT")) {
        return { rows: [], rowCount: 0 };
      }
      // Coin: wallet SELECT FOR UPDATE balance check
      if (sql.includes("SELECT id, balance FROM wallets") && sql.includes("FOR UPDATE")) {
        return { rows: [{ id: walletId, balance: 500 }], rowCount: 1 };
      }
      // Coin: wallet balance deduction
      if (sql.includes("UPDATE wallets SET balance = $1")) {
        return { rows: [], rowCount: 1 };
      }
      // Coin: insert invite_sent coin transaction
      if (sql.includes("INSERT INTO coin_transactions") && sql.includes("invite_sent")) {
        return { rows: [{ id: coinTxId }], rowCount: 1 };
      }
      if (sql.includes("INSERT INTO treat_invites")) {
        return {
          rows: [{ id: inviteId, created_at: new Date("2026-06-09T06:00:00.000Z") }],
          rowCount: 1
        };
      }
      if (sql.includes("WHERE u.id = $1") && sql.includes("LEFT JOIN profile_photos")) {
        return {
          rows: [{
            id: senderId,
            name: "Pavan",
            age: 28,
            bio: "",
            profession: "Engineer",
            gender: "Male",
            height: 175,
            interests: [],
            is_verified: true,
            looking_for: "Dating",
            photo_url: null,
            photo_storage_key: "users/pavan/main.jpg"
          }],
          rowCount: 1
        };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/invites",
      headers: authHeader(senderId),
      payload: { targetUserId: receiverId, venueId, treatType: "drink" }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json().invite).toEqual(expect.objectContaining({
      id: inviteId,
      treatType: "drink",
      intent: "If we both meet and vibe, I'm open to this treat."
    }));
    expect(broadcastToUserMock).toHaveBeenCalledWith(
      receiverId,
      expect.objectContaining({
        type: "invite.received",
        inviteId,
        treatType: "drink",
        profile: expect.objectContaining({ name: "Pavan" })
      })
    );
    await app.close();
  });

  it("rejects custom treat values", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/invites",
      headers: authHeader(senderId),
      payload: { targetUserId: receiverId, venueId, treatType: "cash" }
    });

    expect(response.statusCode).toBe(400);
    expect(broadcastToUserMock).not.toHaveBeenCalled();
    await app.close();
  });

  it("treats an invite back as acceptance of the incoming invite", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("SELECT 1 FROM users u")) {
        return { rows: [{ "?column?": 1 }], rowCount: 1 };
      }
      // Coin: get treat pricing (called twice — once for sender cost check, once in creditReceiverCoins)
      if (sql.includes("SELECT sender_cost, receiver_credit FROM treat_pricing")) {
        return { rows: [{ sender_cost: 50, receiver_credit: 40 }], rowCount: 1 };
      }
      // Coin: wallet lazy-create (ON CONFLICT DO NOTHING) — sender's wallet for cost check
      if (sql.includes("INSERT INTO wallets") && sql.includes("ON CONFLICT")) {
        return { rows: [], rowCount: 0 };
      }
      // Coin: wallet SELECT FOR UPDATE — sender's balance check
      if (sql.includes("SELECT id, balance FROM wallets") && sql.includes("FOR UPDATE")) {
        return { rows: [{ id: walletId, balance: 500 }], rowCount: 1 };
      }
      // Coin: wallet UPDATE balance (deduction for sender, credit for receiver)
      if (sql.includes("UPDATE wallets SET balance = $1")) {
        return { rows: [], rowCount: 1 };
      }
      // Coin: UPDATE wallets SET balance = balance + (credit for receiver)
      if (sql.includes("UPDATE wallets SET balance = balance +")) {
        return { rows: [{ balance: 540 }], rowCount: 1 };
      }
      // Coin: insert coin transactions
      if (sql.includes("INSERT INTO coin_transactions")) {
        return { rows: [{ id: coinTxId }], rowCount: 1 };
      }
      // findIncomingPendingInvite: incoming invite from receiverId -> senderId
      if (sql.includes("SELECT id, sender_id, receiver_id, venue_id, treat_type") && sql.includes("sender_id = $2")) {
        return {
          rows: [{
            id: inviteId,
            sender_id: receiverId,
            receiver_id: senderId,
            venue_id: venueId,
            treat_type: "coffee"
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
      url: "/invites",
      headers: authHeader(senderId),
      payload: { targetUserId: receiverId, venueId, treatType: "coffee" }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ isMatch: true, matchId });
    expect(queryMock.mock.calls.filter(([sql]) => (sql as string).includes("INSERT INTO matches"))).toHaveLength(1);
    expect(queryMock).toHaveBeenCalledWith(
      expect.stringContaining("SET status = CASE WHEN id = $1 THEN $3 ELSE 'accepted' END"),
      [inviteId, matchId, "accepted_by_invite_back", receiverId, senderId]
    );
    expect(broadcastToUserMock).toHaveBeenCalledWith(
      receiverId,
      expect.objectContaining({
        type: "invite.accepted",
        inviteId,
        matchId,
        status: "accepted_by_invite_back"
      })
    );
    await app.close();
  });

  it("reuses an active match instead of creating another invite or chat", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("SELECT 1 FROM users u")) {
        return { rows: [{ "?column?": 1 }], rowCount: 1 };
      }
      if (sql.includes("FROM matches") && sql.includes("unmatched_at IS NULL")) {
        return { rows: [{ id: matchId }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/invites",
      headers: authHeader(senderId),
      payload: { targetUserId: receiverId, venueId, treatType: "drink" }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ isMatch: true, matchId });
    expect(queryMock.mock.calls.some(([sql]) => (sql as string).includes("INSERT INTO treat_invites"))).toBe(false);
    expect(queryMock.mock.calls.some(([sql]) => (sql as string).includes("INSERT INTO matches"))).toBe(false);
    expect(broadcastToUserMock).not.toHaveBeenCalled();
    await app.close();
  });

  it("accepts a pending invite directly and marks it accepted", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("SELECT sender_id, receiver_id") && !sql.includes("venue_id")) {
        return { rows: [{ sender_id: senderId, receiver_id: receiverId }], rowCount: 1 };
      }
      if (sql.includes("SELECT id, sender_id, receiver_id, venue_id") && sql.includes("WHERE id = $1")) {
        return {
          rows: [{
            id: inviteId,
            sender_id: senderId,
            receiver_id: receiverId,
            venue_id: venueId,
            treat_type: "drink"
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
      // creditReceiverCoins: treat pricing
      if (sql.includes("SELECT sender_cost, receiver_credit FROM treat_pricing")) {
        return { rows: [{ sender_cost: 150, receiver_credit: 120 }], rowCount: 1 };
      }
      // creditReceiverCoins: wallet lazy-create
      if (sql.includes("INSERT INTO wallets") && sql.includes("ON CONFLICT")) {
        return { rows: [], rowCount: 0 };
      }
      // creditReceiverCoins: credit receiver wallet
      if (sql.includes("UPDATE wallets SET balance = balance +")) {
        return { rows: [{ balance: 120 }], rowCount: 1 };
      }
      // creditReceiverCoins: insert coin transaction
      if (sql.includes("INSERT INTO coin_transactions")) {
        return { rows: [], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: `/invites/${inviteId}/accept`,
      headers: authHeader(receiverId)
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ matchId });
    expect(queryMock).toHaveBeenCalledWith(
      expect.stringContaining("SET status = CASE WHEN id = $1 THEN $3 ELSE 'accepted' END"),
      [inviteId, matchId, "accepted", senderId, receiverId]
    );
    await app.close();
  });

  it("declines a pending invite without creating a match", async () => {
    const refundTxId = "e1234567-1234-1234-1234-123456789abc";
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      // Decline: expire already-expired invites before the transaction (no-op)
      if (sql.includes("UPDATE treat_invites") && sql.includes("status = 'expired'") && !sql.includes("RETURNING")) {
        return { rows: [], rowCount: 0 };
      }
      // Decline: UPDATE ... SET status = 'declined' ... RETURNING id, sender_id, treat_type
      if (sql.includes("UPDATE treat_invites") && sql.includes("status = 'declined'")) {
        return {
          rows: [{ id: inviteId, sender_id: senderId, treat_type: "coffee" }],
          rowCount: 1
        };
      }
      // refundInviteCoin: JOIN coin_transactions to get original tx amount
      if (sql.includes("JOIN coin_transactions ct ON ct.id = ti.coin_tx_id")) {
        return { rows: [{ id: refundTxId, amount: -50 }], rowCount: 1 };
      }
      // refundInviteCoin: credit sender's wallet
      if (sql.includes("UPDATE wallets SET balance = balance +")) {
        return { rows: [{ balance: 550 }], rowCount: 1 };
      }
      // refundInviteCoin: insert invite_refund coin transaction
      if (sql.includes("INSERT INTO coin_transactions") && sql.includes("invite_refund")) {
        return { rows: [], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: `/invites/${inviteId}/decline`,
      headers: authHeader(receiverId)
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ ok: true });
    expect(queryMock.mock.calls.some(([sql]) => (sql as string).includes("INSERT INTO matches"))).toBe(false);
    await app.close();
  });

  it("returns 402 with insufficient_coins when sender balance is too low", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("SELECT 1 FROM users u")) {
        return { rows: [{ "?column?": 1 }], rowCount: 1 };
      }
      if (sql.includes("SELECT sender_cost, receiver_credit FROM treat_pricing")) {
        return { rows: [{ sender_cost: 150, receiver_credit: 120 }], rowCount: 1 };
      }
      if (sql.includes("INSERT INTO wallets") && sql.includes("ON CONFLICT")) {
        return { rows: [], rowCount: 0 };
      }
      if (sql.includes("SELECT id, balance FROM wallets") && sql.includes("FOR UPDATE")) {
        return { rows: [{ id: walletId, balance: 50 }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/invites",
      headers: authHeader(senderId),
      payload: { targetUserId: receiverId, venueId, treatType: "drink" }
    });

    expect(response.statusCode).toBe(402);
    expect(response.json()).toEqual(expect.objectContaining({
      error: "insufficient_coins",
      required: 150,
      balance: 50
    }));
    expect(queryMock.mock.calls.some(([sql]) => (sql as string).includes("INSERT INTO treat_invites"))).toBe(false);
    await app.close();
  });

  it("rejects decide_together treat type with 400", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/invites",
      headers: authHeader(senderId),
      payload: { targetUserId: receiverId, venueId, treatType: "decide_together" }
    });

    expect(response.statusCode).toBe(400);
    expect(response.json().error).toContain("decide_together");
    await app.close();
  });
});

describe("coin wallet routes", () => {
  beforeEach(() => {
    queryMock.mockReset();
    withTransactionMock.mockReset();
    withTransactionMock.mockImplementation(
      async (callback: (client: { query: typeof queryMock }) => Promise<unknown>) => callback({ query: queryMock })
    );
    // Default auth handler — all coin route tests use the same authenticated user
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });
  });

  it("GET /v1/wallet creates wallet with welcome bonus on first call", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      // ensureWallet: no existing wallet
      if (sql.includes("SELECT id, balance, created_at FROM wallets")) {
        return { rows: [], rowCount: 0 };
      }
      // ensureWallet (inside withTransaction): INSERT wallet with welcome bonus
      if (sql.includes("INSERT INTO wallets") && sql.includes("ON CONFLICT")) {
        return {
          rows: [{ id: walletId, balance: 150, created_at: new Date("2026-01-01T00:00:00.000Z") }],
          rowCount: 1
        };
      }
      // ensureWallet: INSERT welcome_bonus coin_transaction
      if (sql.includes("INSERT INTO coin_transactions") && sql.includes("welcome_bonus")) {
        return { rows: [], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "GET",
      url: "/v1/wallet",
      headers: authHeader(senderId)
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual(expect.objectContaining({ balance: 150 }));
    const insertTxCall = queryMock.mock.calls.find(([sql]: [string]) =>
      sql.includes("INSERT INTO coin_transactions") && sql.includes("welcome_bonus")
    );
    expect(insertTxCall).toBeDefined();
    await app.close();
  });

  it("GET /v1/wallet returns existing wallet without re-creating it", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("SELECT id, balance, created_at FROM wallets")) {
        return {
          rows: [{ id: walletId, balance: 300, created_at: new Date("2026-01-01T00:00:00.000Z") }],
          rowCount: 1
        };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "GET",
      url: "/v1/wallet",
      headers: authHeader(senderId)
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual(expect.objectContaining({ balance: 300 }));
    expect(withTransactionMock).not.toHaveBeenCalled();
    await app.close();
  });

  it("GET /v1/wallet/packages returns active packages ordered by position", async () => {
    const packages = [
      { id: pkgId, slug: "starter_pack", coins: 100, priceInr: 14900, bonusPct: 0 },
      { id: "d9999999-0000-0000-0000-000000000001", slug: "popular_pack", coins: 300, priceInr: 42500, bonusPct: 0 }
    ];
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM coin_packages")) {
        return { rows: packages, rowCount: packages.length };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "GET",
      url: "/v1/wallet/packages",
      headers: authHeader(senderId)
    });

    expect(response.statusCode).toBe(200);
    expect(response.json().packages).toHaveLength(2);
    expect(response.json().packages[0].slug).toBe("starter_pack");
    await app.close();
  });

  it("POST /v1/wallet/purchase credits coins and returns new balance", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      // Fetch package by slug
      if (sql.includes("FROM coin_packages WHERE slug = $1")) {
        return { rows: [{ id: pkgId, coins: 100, price_inr: 14900 }], rowCount: 1 };
      }
      // Inside withTransaction: INSERT wallet ON CONFLICT returning current balance
      if (sql.includes("INSERT INTO wallets") && sql.includes("ON CONFLICT")) {
        return { rows: [{ balance: 150 }], rowCount: 1 };
      }
      // UPDATE wallets SET balance = newBalance
      if (sql.includes("UPDATE wallets SET balance = $1")) {
        return { rows: [], rowCount: 1 };
      }
      // INSERT coin_transaction RETURNING id
      if (sql.includes("INSERT INTO coin_transactions") && sql.includes("purchase")) {
        return { rows: [{ id: coinTxId }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/v1/wallet/purchase",
      headers: authHeader(senderId),
      payload: { slug: "starter_pack" }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({
      ok: true,
      coinsAdded: 100,
      newBalance: 250,
      transactionId: coinTxId
    });
    await app.close();
  });

  it("POST /v1/wallet/purchase returns 404 for unknown package slug", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM coin_packages WHERE slug = $1")) {
        return { rows: [], rowCount: 0 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/v1/wallet/purchase",
      headers: authHeader(senderId),
      payload: { slug: "nonexistent_pack" }
    });

    expect(response.statusCode).toBe(404);
    await app.close();
  });

  it("POST /v1/wallet/purchase returns 400 when slug is missing", async () => {
    const app = await buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/v1/wallet/purchase",
      headers: authHeader(senderId),
      payload: {}
    });

    expect(response.statusCode).toBe(400);
    await app.close();
  });

  it("GET /v1/wallet/transactions returns paginated transactions with hasMore=true", async () => {
    const txRows = Array.from({ length: 21 }, (_, i) => ({
      id: `tx-${i}`,
      type: i === 0 ? "welcome_bonus" : "invite_sent",
      amount: i === 0 ? 150 : -50,
      balance_after: 150 - i * 50,
      metadata: null,
      created_at: new Date(`2026-01-${String(21 - i).padStart(2, "0")}T00:00:00.000Z`)
    }));
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM coin_transactions")) {
        return { rows: txRows, rowCount: txRows.length };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "GET",
      url: "/v1/wallet/transactions",
      headers: authHeader(senderId)
    });

    expect(response.statusCode).toBe(200);
    const body = response.json();
    expect(body.transactions).toHaveLength(20);
    expect(body.hasMore).toBe(true);
    await app.close();
  });

  it("GET /v1/wallet/transactions returns hasMore=false when results fit in one page", async () => {
    const txRows = [
      { id: coinTxId, type: "welcome_bonus", amount: 150, balance_after: 150, metadata: null, created_at: new Date("2026-01-01T00:00:00.000Z") }
    ];
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM coin_transactions")) {
        return { rows: txRows, rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "GET",
      url: "/v1/wallet/transactions",
      headers: authHeader(senderId)
    });

    expect(response.statusCode).toBe(200);
    expect(response.json().hasMore).toBe(false);
    await app.close();
  });

  it("GET /v1/wallet/treat-pricing returns active pricing for all treat types", async () => {
    const pricing = [
      { treatType: "coffee", senderCost: 50, receiverCredit: 40 },
      { treatType: "dessert", senderCost: 75, receiverCredit: 60 },
      { treatType: "starter", senderCost: 100, receiverCredit: 80 },
      { treatType: "drink", senderCost: 150, receiverCredit: 120 }
    ];
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM treat_pricing")) {
        return { rows: pricing, rowCount: pricing.length };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "GET",
      url: "/v1/wallet/treat-pricing",
      headers: authHeader(senderId)
    });

    expect(response.statusCode).toBe(200);
    expect(response.json().pricing).toHaveLength(4);
    expect(response.json().pricing[0]).toEqual({ treatType: "coffee", senderCost: 50, receiverCredit: 40 });
    await app.close();
  });
});
