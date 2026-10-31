import { buildApp } from "../../src/app.js";

describe("app integration", () => {
  it("returns 404 for unknown routes", async () => {
    const app = await buildApp();

    const response = await app.inject({
      method: "GET",
      url: "/does-not-exist"
    });

    expect(response.statusCode).toBe(404);
    await app.close();
  });
});

