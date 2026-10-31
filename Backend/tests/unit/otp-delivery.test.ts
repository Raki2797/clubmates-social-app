import { beforeEach, describe, expect, it, vi } from "vitest";

async function loadDeliveryServiceWithEnv(envValues: Record<string, string | undefined>) {
  vi.resetModules();
  Object.assign(process.env, envValues);
  return import("../../src/services/otpDelivery.js");
}

describe("otp delivery", () => {
  beforeEach(() => {
    vi.unstubAllGlobals();
    process.env.MSG91_AUTH_KEY = "";
    process.env.MSG91_TEMPLATE_ID = "";
    process.env.MSG91_SENDER_ID = "";
    process.env.MSG91_API_BASE_URL = "";
    process.env.MSG91_TIMEOUT_MS = "";
    process.env.OTP_EXPIRY_MINUTES = "5";
  });

  it("sends OTPs through MSG91 with the stored code", async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response(
      JSON.stringify({ type: "success", request_id: "request-1" }),
      { status: 200 }
    ));
    vi.stubGlobal("fetch", fetchMock);

    const { deliverOtp } = await loadDeliveryServiceWithEnv({
      MSG91_AUTH_KEY: "auth-key",
      MSG91_TEMPLATE_ID: "template-id",
      MSG91_API_BASE_URL: "https://msg91.example.test",
      OTP_EXPIRY_MINUTES: "7"
    });

    await deliverOtp("+919876543210", "654321");

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0] as [URL, RequestInit];
    expect(url.origin).toBe("https://msg91.example.test");
    expect(url.pathname).toBe("/api/v5/otp");
    expect(url.searchParams.get("template_id")).toBe("template-id");
    expect(url.searchParams.get("mobile")).toBe("919876543210");
    expect(url.searchParams.get("authkey")).toBe("auth-key");
    expect(url.searchParams.get("otp")).toBe("654321");
    expect(url.searchParams.get("otp_expiry")).toBe("7");
    expect(url.searchParams.get("otp_length")).toBe("6");
    expect(url.searchParams.get("realTimeResponse")).toBe("1");
    expect(init).toMatchObject({
      method: "POST",
      body: "{}"
    });
  });

  it("does nothing when MSG91 is not configured", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    const { deliverOtp } = await loadDeliveryServiceWithEnv({
      MSG91_AUTH_KEY: "",
      MSG91_TEMPLATE_ID: ""
    });

    await deliverOtp("+919876543210", "654321");

    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("raises a delivery error when MSG91 rejects the request", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(
      JSON.stringify({ type: "error", message: "The provided flow ID or template ID is invalid." }),
      { status: 200 }
    )));

    const { deliverOtp, OtpDeliveryError } = await loadDeliveryServiceWithEnv({
      MSG91_AUTH_KEY: "auth-key",
      MSG91_TEMPLATE_ID: "bad-template",
      MSG91_API_BASE_URL: "https://msg91.example.test"
    });

    const result = deliverOtp("+919876543210", "654321");
    await expect(result).rejects.toBeInstanceOf(OtpDeliveryError);
    await expect(result).rejects.toThrow("template ID is invalid");
  });
});
