import { beforeEach, vi } from "vitest";

const { queryMock, withTransactionMock, deleteProfilePhotoObjectsMock } = vi.hoisted(() => ({
  queryMock: vi.fn(),
  withTransactionMock: vi.fn(),
  deleteProfilePhotoObjectsMock: vi.fn()
}));

vi.mock("../../src/db/pool.js", () => ({
  query: queryMock,
  withTransaction: withTransactionMock,
  closePool: vi.fn()
}));

vi.mock("../../src/services/profilePhotoStorage.js", () => ({
  deleteProfilePhotoObjects: deleteProfilePhotoObjectsMock
}));

import { purgeExpiredDeletedUsers } from "../../src/jobs/accountDeletion.js";

const expiredUserIds = [
  "505f7fc3-2d06-4b96-aa90-6380f511ffde",
  "606f7fc3-2d06-4b96-aa90-6380f511ffdf"
];
const expiredPhones = ["+919876543210", "+919876543211"];

describe("account deletion purge", () => {
  beforeEach(() => {
    queryMock.mockReset();
    withTransactionMock.mockReset();
    deleteProfilePhotoObjectsMock.mockReset();
  });

  it("does nothing when no scheduled deletions have expired", async () => {
    queryMock.mockResolvedValueOnce({ rows: [], rowCount: 0 });

    const deletedCount = await purgeExpiredDeletedUsers();

    expect(deletedCount).toBe(0);
    expect(deleteProfilePhotoObjectsMock).not.toHaveBeenCalled();
    expect(withTransactionMock).not.toHaveBeenCalled();
  });

  it("deletes dependent user data before permanently deleting expired accounts", async () => {
    const clientQueryMock = vi.fn(async (sql: string) => {
      if (sql.includes("WITH deleted AS")) {
        return { rows: [{ deleted_count: "2" }], rowCount: 1 };
      }
      return { rows: [], rowCount: 1 };
    });

    queryMock
      .mockResolvedValueOnce({
        rows: [
          { id: expiredUserIds[0], phone_e164: expiredPhones[0] },
          { id: expiredUserIds[1], phone_e164: expiredPhones[1] }
        ],
        rowCount: 2
      })
      .mockResolvedValueOnce({
        rows: [
          { storage_key: "profile-photos/user-a/main.jpg" },
          { storage_key: "profile-photos/user-b/main.jpg" }
        ],
        rowCount: 2
      });

    withTransactionMock.mockImplementation(async (cb: (client: { query: typeof clientQueryMock }) => Promise<number>) => {
      return cb({ query: clientQueryMock });
    });

    const deletedCount = await purgeExpiredDeletedUsers();

    expect(deletedCount).toBe(2);
    expect(deleteProfilePhotoObjectsMock).toHaveBeenCalledWith([
      "profile-photos/user-a/main.jpg",
      "profile-photos/user-b/main.jpg"
    ]);

    expect(clientQueryMock).toHaveBeenCalledWith(
      expect.stringContaining("DELETE FROM otp_codes"),
      [expiredPhones]
    );
    expect(clientQueryMock).toHaveBeenCalledWith(
      expect.stringContaining("DELETE FROM refresh_tokens"),
      [expiredUserIds]
    );
    expect(clientQueryMock).toHaveBeenCalledWith(
      expect.stringContaining("DELETE FROM device_tokens"),
      [expiredUserIds]
    );
    expect(clientQueryMock).toHaveBeenCalledWith(
      expect.stringContaining("DELETE FROM messages WHERE sender_id"),
      [expiredUserIds]
    );
    expect(clientQueryMock).toHaveBeenCalledWith(
      expect.stringContaining("DELETE FROM messages\n        WHERE match_id IN"),
      [expiredUserIds]
    );
    expect(clientQueryMock).toHaveBeenCalledWith(
      expect.stringContaining("DELETE FROM reports"),
      [expiredUserIds]
    );
    expect(clientQueryMock).toHaveBeenCalledWith(
      expect.stringContaining("DELETE FROM blocks"),
      [expiredUserIds]
    );
    expect(clientQueryMock).toHaveBeenCalledWith(
      expect.stringContaining("DELETE FROM swipes"),
      [expiredUserIds]
    );
    expect(clientQueryMock).toHaveBeenCalledWith(
      expect.stringContaining("DELETE FROM checkins"),
      [expiredUserIds]
    );
    expect(clientQueryMock).toHaveBeenCalledWith(
      expect.stringContaining("DELETE FROM sos_events"),
      [expiredUserIds]
    );
    expect(clientQueryMock).toHaveBeenCalledWith(
      expect.stringContaining("DELETE FROM matches"),
      [expiredUserIds]
    );
    expect(clientQueryMock).toHaveBeenCalledWith(
      expect.stringContaining("DELETE FROM profile_prompts"),
      [expiredUserIds]
    );
    expect(clientQueryMock).toHaveBeenCalledWith(
      expect.stringContaining("DELETE FROM profile_photos"),
      [expiredUserIds]
    );
    expect(clientQueryMock).toHaveBeenCalledWith(
      expect.stringContaining("DELETE FROM users"),
      [expiredUserIds]
    );
  });
});
