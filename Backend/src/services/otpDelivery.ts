import { env } from "../config/env.js";

export class OtpDeliveryError extends Error {
  readonly provider = "MSG91";
  readonly statusCode?: number;
  readonly responseBody?: string;

  constructor(message: string, options: { statusCode?: number; responseBody?: string } = {}) {
    super(message);
    this.name = "OtpDeliveryError";
    this.statusCode = options.statusCode;
    this.responseBody = options.responseBody;
  }
}

function msg91Mobile(phoneE164: string): string {
  return phoneE164.replace(/^\+/, "");
}

function parseJsonObject(raw: string): Record<string, unknown> | undefined {
  if (!raw) { return undefined; }

  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? parsed as Record<string, unknown>
      : undefined;
  } catch {
    return undefined;
  }
}

function responseMessage(payload: Record<string, unknown> | undefined, fallback: string): string {
  const message = payload?.message;
  return typeof message === "string" && message.trim() ? message : fallback;
}

function assertMsg91Success(response: Response, responseText: string): void {
  const payload = parseJsonObject(responseText);
  const type = typeof payload?.type === "string" ? payload.type.toLowerCase() : undefined;

  if (!response.ok) {
    throw new OtpDeliveryError(
      responseMessage(payload, `MSG91 OTP request failed with status ${response.status}`),
      { statusCode: response.status, responseBody: responseText }
    );
  }

  if (type === "error") {
    throw new OtpDeliveryError(
      responseMessage(payload, "MSG91 rejected the OTP request"),
      { statusCode: response.status, responseBody: responseText }
    );
  }

  if (type !== "success") {
    throw new OtpDeliveryError(
      responseMessage(payload, "MSG91 returned an unexpected OTP response"),
      { statusCode: response.status, responseBody: responseText }
    );
  }
}

export async function deliverOtp(phoneE164: string, code: string): Promise<void> {
  const msg91 = env.msg91;
  if (!msg91) {
    return;
  }

  const url = new URL("/api/v5/otp", msg91.apiBaseUrl);
  url.searchParams.set("template_id", msg91.templateId);
  url.searchParams.set("mobile", msg91Mobile(phoneE164));
  url.searchParams.set("authkey", msg91.authKey);
  url.searchParams.set("otp", code);
  url.searchParams.set("otp_expiry", String(env.otpExpiryMinutes));
  url.searchParams.set("otp_length", String(code.length));
  url.searchParams.set("realTimeResponse", "1");

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), msg91.timeoutMs);

  let response: Response;
  try {
    response = await fetch(url, {
      method: "POST",
      headers: {
        accept: "application/json",
        "content-type": "application/json"
      },
      body: "{}",
      signal: controller.signal
    });
  } catch (error) {
    const message = error instanceof Error && error.name === "AbortError"
      ? "MSG91 OTP request timed out"
      : error instanceof Error
        ? error.message
        : "MSG91 OTP request failed";
    throw new OtpDeliveryError(message);
  } finally {
    clearTimeout(timeout);
  }

  assertMsg91Success(response, await response.text());
}
