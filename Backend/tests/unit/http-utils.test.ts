import { asString, asStringArray } from "../../src/utils/http.js";

describe("http utils", () => {
  it("asString returns string values only", () => {
    expect(asString("clubmates")).toBe("clubmates");
    expect(asString(42)).toBeUndefined();
    expect(asString({})).toBeUndefined();
    expect(asString(undefined)).toBeUndefined();
  });

  it("asStringArray keeps only string entries", () => {
    expect(asStringArray(["a", "b", 1, null, "c"])).toEqual(["a", "b", "c"]);
    expect(asStringArray("not-array")).toEqual([]);
    expect(asStringArray(undefined)).toEqual([]);
  });
});

