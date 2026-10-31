import { describe, expect, it, vi } from "vitest";

describe("profile photo storage", () => {
  it("retries a transient upload failure using the same object path", async () => {
    vi.resetModules();
    process.env.SUPABASE_URL = "https://supabase.example.com";
    process.env.SUPABASE_SERVICE_ROLE_KEY = "service-role-key";
    process.env.SUPABASE_PROFILE_PHOTOS_BUCKET = "profile-photos";

    const fetchMock = vi.fn()
      .mockRejectedValueOnce(new TypeError("temporary network failure"))
      .mockResolvedValueOnce(new Response("", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);

    const { uploadProfilePhotoObject } = await import("../../src/services/profilePhotoStorage.js");
    await uploadProfilePhotoObject(
      "user/photo-1.jpg",
      Buffer.from("jpeg"),
      "image/jpeg"
    );

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(fetchMock.mock.calls.map(([url]) => url)).toEqual([
      "https://supabase.example.com/storage/v1/object/profile-photos/user/photo-1.jpg",
      "https://supabase.example.com/storage/v1/object/profile-photos/user/photo-1.jpg"
    ]);
  });

  it("deletes objects through the Supabase Storage delete endpoint", async () => {
    vi.resetModules();
    process.env.SUPABASE_URL = "https://supabase.example.com";
    process.env.SUPABASE_SERVICE_ROLE_KEY = "service-role-key";
    process.env.SUPABASE_PROFILE_PHOTOS_BUCKET = "profile-photos";

    const fetchMock = vi.fn().mockResolvedValue(new Response("[]", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);

    const { deleteProfilePhotoObjects } = await import("../../src/services/profilePhotoStorage.js");
    await deleteProfilePhotoObjects(["user/photo-1.jpg", "user/photo-2.jpg"]);

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock).toHaveBeenCalledWith(
      "https://supabase.example.com/storage/v1/object/profile-photos",
      expect.objectContaining({
        method: "DELETE",
        body: JSON.stringify({ prefixes: ["user/photo-1.jpg", "user/photo-2.jpg"] })
      })
    );
  });
});
