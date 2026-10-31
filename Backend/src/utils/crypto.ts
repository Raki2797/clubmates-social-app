import crypto from "node:crypto";

export function randomToken(bytes = 32): string {
  return crypto.randomBytes(bytes).toString("base64url");
}

export function hashValue(value: string): string {
  return crypto.createHash("sha256").update(value).digest("hex");
}

export function randomOtp(): string {
  return String(crypto.randomInt(100000, 999999));
}
