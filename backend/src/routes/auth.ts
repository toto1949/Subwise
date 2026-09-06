import type { FastifyPluginAsync } from "fastify";
import argon2 from "argon2";
import { randomBytes } from "node:crypto";
import { z } from "zod";
import { revokeAppleAuthorization } from "../services/apple-authorization.js";
import { PlaidClient } from "../services/plaid-client.js";
import { decryptToken } from "../lib/token-encryption.js";
import { AppError } from "../lib/errors.js";

const plugin: FastifyPluginAsync = async (app) => {
  app.post("/auth/apple", async (request, reply) => {
    const body = z.object({ identityToken: z.string().min(20), authorizationCode: z.string().min(1).nullish(), displayName: z.string().max(100).optional() }).parse(request.body);
    const identity = await app.verifyAppleToken(body.identityToken);
    const user = await app.db.user.upsert({ where: { appleSubject: identity.subject }, update: { ...(identity.email ? { email: identity.email } : {}), ...(body.displayName ? { displayName: body.displayName } : {}) }, create: { appleSubject: identity.subject, email: identity.email, displayName: body.displayName } });
    const refreshToken = randomBytes(48).toString("base64url");
    const session = await app.db.userSession.create({ data: { userId: user.id, refreshTokenHash: await argon2.hash(refreshToken), expiresAt: new Date(Date.now() + 30 * 86_400_000) } });
    return reply.send({ accessToken: await app.issueAccessToken(user.id), refreshToken: `${session.id}.${refreshToken}`, expiresIn: 900 });
  });

  app.post("/auth/refresh", async (request) => {
    const { refreshToken } = z.object({ refreshToken: z.string() }).parse(request.body);
    const [sessionId, rawToken] = refreshToken.split(".");
    if (!sessionId || !rawToken) throw new AppError("INVALID_REFRESH_TOKEN", "Refresh token is invalid", 401);
    const session = await app.db.userSession.findUnique({ where: { id: sessionId } });
    if (!session || session.revokedAt || session.expiresAt < new Date() || !(await argon2.verify(session.refreshTokenHash, rawToken))) throw new AppError("INVALID_REFRESH_TOKEN", "Refresh token is invalid or expired", 401);
    const nextToken = randomBytes(48).toString("base64url");
    await app.db.userSession.update({ where: { id: session.id }, data: { refreshTokenHash: await argon2.hash(nextToken) } });
    return { accessToken: await app.issueAccessToken(session.userId), refreshToken: `${session.id}.${nextToken}`, expiresIn: 900 };
  });

  app.post("/auth/logout", { preHandler: app.authenticate }, async (request, reply) => {
    await app.db.userSession.updateMany({ where: { userId: request.userId, revokedAt: null }, data: { revokedAt: new Date() } });
    return reply.status(204).send();
  });

  app.delete("/account", { preHandler: app.authenticate }, async (request, reply) => {
    const body = z.object({ identityToken: z.string().min(20), authorizationCode: z.string().min(1) }).parse(request.body);
    const user = await app.db.user.findUnique({ where: { id: request.userId } });
    if (!user) return reply.status(204).send();
    const identity = await app.verifyAppleToken(body.identityToken);
    if (identity.subject !== user.appleSubject) throw new AppError("APPLE_ACCOUNT_MISMATCH", "Use the Apple account linked to this Subwise account.", 403);
    // Keep the account retryable if any provider cleanup fails.
    if (!app.config.APPLE_TEAM_ID || !app.config.APPLE_KEY_ID || !app.config.APPLE_PRIVATE_KEY) {
      throw new AppError("APPLE_REVOCATION_NOT_CONFIGURED", "Account deletion is temporarily unavailable. Please try again later.", 503);
    }
    const connections = await app.db.institutionConnection.findMany({ where: { userId: request.userId } });
    const plaid = new PlaidClient(app.config);
    for (const connection of connections) {
      if (!app.config.DATA_ENCRYPTION_KEY) throw new AppError("PLAID_NOT_CONFIGURED", "Bank access could not be removed. Please try again later.", 503);
      await plaid.removeItem(decryptToken(connection.encryptedAccessToken, app.config.DATA_ENCRYPTION_KEY));
      await app.db.institutionConnection.deleteMany({ where: { id: connection.id, userId: request.userId } });
    }
    await revokeAppleAuthorization(app.config, body.authorizationCode, user.appleSubject, app.verifyAppleToken);
    await app.db.$transaction(async (tx) => {
      // SetNull would leave member display names/emails visible in somebody else's household.
      await tx.householdMember.deleteMany({ where: { userId: request.userId } });
      await tx.user.delete({ where: { id: request.userId } });
    });
    return reply.status(204).send();
  });
};
export default plugin;
