import jwt, { JwtPayload } from "jsonwebtoken";
import { env } from "../config/env.js";

export type AuthContext = {
  userId: string;
  phone: string;
};

export function signAccessToken(auth: AuthContext): string {
  return jwt.sign(
    { phone: auth.phone },
    env.jwtSecret,
    {
      algorithm: "HS256",
      expiresIn: env.accessTokenTtlSeconds,
      subject: auth.userId
    }
  );
}

export function verifyAccessToken(token: string): AuthContext {
  const decoded = jwt.verify(token, env.jwtSecret, {
    algorithms: ["HS256"]
  }) as JwtPayload;

  if (!decoded.sub || typeof decoded.phone !== "string") {
    throw new Error("Invalid access token payload");
  }

  return {
    userId: decoded.sub,
    phone: decoded.phone
  };
}
