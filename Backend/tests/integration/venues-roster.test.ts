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
  withSignedPhotoUrls: withSignedPhotoUrlsMock
}));

import { buildApp } from "../../src/app.js";

function authHeader(userId: string): Record<string, string> {
  const token = signAccessToken({ userId, phone: "+911234567890" });
  return { authorization: `Bearer ${token}` };
}

const me = "505f7fc3-2d06-4b96-aa90-6380f511ffde";
const venueId = "abf264f1-6cea-4cb9-bdaf-a7b9522c9d2a";

describe("venues roster visibility", () => {
  beforeEach(() => {
    queryMock.mockReset();
    withSignedPhotoUrlsMock.mockReset();
  });

  it("returns full active roster profiles with prompts and signed photos", async () => {
    withSignedPhotoUrlsMock.mockImplementation(async (photos) => photos.map((photo: {
      cdn_url: string | null;
      position: number;
    }) => ({
      ...photo,
      cdn_url: `https://cdn.example.com/u1-${photo.position}.jpg`
    })));
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM checkins c")) {
        return {
          rows: [
            {
              id: "4f34e495-a51f-498c-86a9-5c2cba3a9e5a",
              name: "Dhanush",
              age: 21,
              bio: "Tester",
              profession: "Chef",
              gender: "Male",
              height: 171,
              interests: ["Travel"],
              is_verified: false,
              is_ghost_mode: false,
              looking_for: "Long-term relationship"
            }
          ],
          rowCount: 1
        };
      }
      if (sql.includes("FROM profile_prompts")) {
        return {
          rows: [
            {
              id: "9faebdc6-a641-4ba4-9d84-b7a6b3bb0e89",
              question: "My perfect weekend",
              answer: "Trying a new restaurant",
              position: 0
            }
          ],
          rowCount: 1
        };
      }
      if (sql.includes("FROM profile_photos")) {
        return {
          rows: [
            {
              id: "7bb1e278-55e8-431d-a5f7-12fc1fdb9387",
              storage_key: "users/dhanush/main.jpg",
              cdn_url: "https://legacy.cdn/u1-main.jpg",
              position: 0
            },
            {
              id: "6a5ae934-514a-4f6c-ae91-038932870fbf",
              storage_key: "users/dhanush/second.jpg",
              cdn_url: "https://legacy.cdn/u1-second.jpg",
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
      url: `/venues/${venueId}/roster`,
      headers: authHeader(me)
    });

    expect(response.statusCode).toBe(200);
    const body = response.json();
    expect(body.roster).toHaveLength(1);
    expect(body.roster[0].id).toBe("4f34e495-a51f-498c-86a9-5c2cba3a9e5a");
    expect(body.roster[0].lookingFor).toBe("Long-term relationship");
    expect(body.roster[0].prompts).toEqual([
      expect.objectContaining({
        question: "My perfect weekend",
        answer: "Trying a new restaurant"
      })
    ]);
    expect(body.roster[0].photos).toEqual([
      expect.objectContaining({
        cdnUrl: "https://cdn.example.com/u1-0.jpg",
        position: 0
      }),
      expect.objectContaining({
        cdnUrl: "https://cdn.example.com/u1-1.jpg",
        position: 1
      })
    ]);
    expect(withSignedPhotoUrlsMock).toHaveBeenCalledTimes(1);
    const rosterSQL = queryMock.mock.calls
      .map(([sql]) => sql as string)
      .find((sql) => sql.includes("FROM checkins c"));
    expect(rosterSQL).toContain("SELECT 1 FROM matches m");
    expect(rosterSQL).toContain("u.is_ghost_mode = false");
    expect(rosterSQL).not.toContain("latest.unmatched_at IS NOT NULL");
    await app.close();
  });

  it("returns empty roster when no eligible users", async () => {
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM checkins c")) {
        return { rows: [], rowCount: 0 };
      }
      return { rows: [], rowCount: 0 };
    });

    const app = await buildApp();
    const response = await app.inject({
      method: "GET",
      url: `/venues/${venueId}/roster`,
      headers: authHeader(me)
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ roster: [] });
    await app.close();
  });

  it("falls back to stored cdn_url when signed URL is unavailable", async () => {
    withSignedPhotoUrlsMock.mockImplementation(async (photos) => photos);
    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM checkins c")) {
        return {
          rows: [
            {
              id: "4f34e495-a51f-498c-86a9-5c2cba3a9e5a",
              name: "Dhanush",
              age: 21,
              bio: "Tester",
              profession: "Chef",
              gender: "Male",
              height: 171,
              interests: ["Travel"],
              is_verified: false,
              is_ghost_mode: false,
              looking_for: ""
            }
          ],
          rowCount: 1
        };
      }
      if (sql.includes("FROM profile_prompts")) {
        return { rows: [], rowCount: 0 };
      }
      if (sql.includes("FROM profile_photos")) {
        return {
          rows: [{
            id: "7bb1e278-55e8-431d-a5f7-12fc1fdb9387",
            storage_key: "users/dhanush/main.jpg",
            cdn_url: "https://legacy.cdn/u1.jpg",
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
      url: `/venues/${venueId}/roster`,
      headers: authHeader(me)
    });

    expect(response.statusCode).toBe(200);
    expect(response.json().roster[0].photos[0].cdnUrl).toBe("https://legacy.cdn/u1.jpg");
    await app.close();
  });

  it("handles mixed photo signing results without failing roster", async () => {
    withSignedPhotoUrlsMock.mockImplementation(async (photos) => photos.map((photo: {
      storage_key: string;
      cdn_url: string | null;
    }) => ({
      ...photo,
      cdn_url: photo.storage_key.includes("missing")
        ? photo.cdn_url
        : "https://cdn.example.com/signed.jpg"
    })));

    queryMock.mockImplementation(async (sql: string) => {
      if (sql.includes("SELECT is_active, deletion_scheduled_at")) {
        return { rows: [{ is_active: true, deletion_scheduled_at: null }], rowCount: 1 };
      }
      if (sql.includes("FROM checkins c")) {
        return {
          rows: [
            {
              id: "4f34e495-a51f-498c-86a9-5c2cba3a9e5a",
              name: "Dhanush",
              age: 21,
              bio: "Tester",
              profession: "Chef",
              gender: "Male",
              height: 171,
              interests: ["Travel"],
              is_verified: false,
              is_ghost_mode: false,
              looking_for: ""
            },
            {
              id: "a6f574ab-4383-4a66-b28e-6fef49eb9f5a",
              name: "Ravi",
              age: 24,
              bio: "Hello",
              profession: "Designer",
              gender: "Male",
              height: 175,
              interests: ["Music"],
              is_verified: true,
              is_ghost_mode: false,
              looking_for: ""
            }
          ],
          rowCount: 2
        };
      }
      if (sql.includes("FROM profile_prompts")) {
        return { rows: [], rowCount: 0 };
      }
      if (sql.includes("FROM profile_photos")) {
        const userId = queryMock.mock.calls.at(-1)?.[1]?.[0];
        return {
          rows: [{
            id: userId === "4f34e495-a51f-498c-86a9-5c2cba3a9e5a"
              ? "7bb1e278-55e8-431d-a5f7-12fc1fdb9387"
              : "6a5ae934-514a-4f6c-ae91-038932870fbf",
            storage_key: userId === "4f34e495-a51f-498c-86a9-5c2cba3a9e5a"
              ? "users/dhanush/missing.jpg"
              : "users/ravi/main.jpg",
            cdn_url: userId === "4f34e495-a51f-498c-86a9-5c2cba3a9e5a"
              ? "https://legacy.cdn/u1.jpg"
              : null,
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
      url: `/venues/${venueId}/roster`,
      headers: authHeader(me)
    });

    expect(response.statusCode).toBe(200);
    const body = response.json();
    expect(body.roster).toHaveLength(2);
    expect(body.roster[0].photos[0].cdnUrl).toBe("https://legacy.cdn/u1.jpg");
    expect(body.roster[1].photos[0].cdnUrl).toBe("https://cdn.example.com/signed.jpg");
    await app.close();
  });
});
