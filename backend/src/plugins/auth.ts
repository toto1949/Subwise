import fp from "fastify-plugin";
import { createRemoteJWKSet, jwtVerify, SignJWT } from "jose";
import { AppError } from "../lib/errors.js";

declare module "fastify" {
  interface FastifyRequest { userId: string }
  interface FastifyInstance {
    authenticate: (request: import("fastify").FastifyRequest) => Promise<void>;
    issueAccessToken: (userId: string) => Promise<string>;
    verifyAppleToken: (token: string) => Promise<{ subject: string; email?: string }>;
  }
}

export default fp(async (app) => {
  const secret = new TextEncoder().encode(app.config.ACCESS_TOKEN_SECRET);
  const appleKeys = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));
  app.decorateRequest("userId", "");
  app.decorate("authenticate", async (request) => {
    const header = request.headers.authorization;
    if (!header?.startsWith("Bearer ")) throw new AppError("UNAUTHORIZED", "Authentication required", 401);
    try {
      const { payload } = await jwtVerify(header.slice(7), secret, { issuer: "subwise-api", audience: "subwise-ios" });
      if (typeof payload.sub !== "string") throw new Error("Missing subject");
      request.userId = payload.sub;
    } catch { throw new AppError("INVALID_ACCESS_TOKEN", "The access token is invalid or expired", 401); }
  });
  app.decorate("issueAccessToken", (userId) => new SignJWT({ scope: "user" }).setProtectedHeader({ alg: "HS256" }).setSubject(userId).setIssuer("subwise-api").setAudience("subwise-ios").setIssuedAt().setExpirationTime("15m").sign(secret));
  app.decorate("verifyAppleToken", async (token) => {
    try {
      const { payload } = await jwtVerify(token, appleKeys, { issuer: "https://appleid.apple.com", audience: app.config.APPLE_CLIENT_ID });
      if (typeof payload.sub !== "string") throw new Error("Missing subject");
      return { subject: payload.sub, ...(typeof payload.email === "string" ? { email: payload.email } : {}) };
    } catch {
      throw new AppError("INVALID_APPLE_TOKEN", "Apple identity token is invalid or expired", 401);
    }
  });
});
