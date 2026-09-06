import Fastify from "fastify";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadConfig } from "../src/config.js";
import { AppError, errorHandler } from "../src/lib/errors.js";
import { encryptToken } from "../src/lib/token-encryption.js";
import authRoutes from "../src/routes/auth.js";
import discoveryRoutes from "../src/routes/discovery.js";
import { revokeAppleAuthorization } from "../src/services/apple-authorization.js";
import { PlaidClient } from "../src/services/plaid-client.js";
vi.mock("../src/services/apple-authorization.js", () => ({ revokeAppleAuthorization: vi.fn() }));
const userId = "00000000-0000-4000-8000-000000000001", connectionId = "00000000-0000-4000-8000-000000000002";
const config = loadConfig({ DATABASE_URL: "postgresql://localhost/test", ACCESS_TOKEN_SECRET: "x".repeat(32), APPLE_CLIENT_ID: "com.toto.Subwise", APPLE_TEAM_ID: "test-team", APPLE_KEY_ID: "test-key", APPLE_PRIVATE_KEY: "test-key", DATA_ENCRYPTION_KEY: "k".repeat(32) });
const headers = { authorization: "Bearer test" };
const payload = { identityToken: "i".repeat(30), authorizationCode: "fresh-code" };
const apps: ReturnType<typeof Fastify>[] = [];
async function setup() {
  const app = Fastify(); apps.push(app);
  const db = {
    user: { findUnique: vi.fn().mockResolvedValue({ id: userId, appleSubject: "apple-owner" }), delete: vi.fn().mockResolvedValue({}) },
    institutionConnection: { findMany: vi.fn().mockResolvedValue([]), findFirst: vi.fn().mockResolvedValue(null), deleteMany: vi.fn().mockResolvedValue({ count: 1 }) },
    householdMember: { deleteMany: vi.fn().mockResolvedValue({ count: 1 }) },
    $transaction: vi.fn()
  };
  db.$transaction.mockImplementation((fn) => fn(db));
  app.decorate("config", config); app.decorate("db", db as never);
  app.decorate("authenticate", async (request) => {
    if (!request.headers.authorization) throw new AppError("UNAUTHORIZED", "Authentication required", 401);
    request.userId = userId;
  });
  app.decorate("verifyAppleToken", vi.fn().mockResolvedValue({ subject: "apple-owner" }));
  app.setErrorHandler(errorHandler); app.register(authRoutes); app.register(discoveryRoutes);
  await app.ready(); return { app, db };
}
beforeEach(() => { vi.mocked(revokeAppleAuthorization).mockReset().mockResolvedValue(); });
afterEach(async () => { await Promise.all(apps.splice(0).map((app) => app.close())); vi.restoreAllMocks(); });
describe("account controls", () => {
  it("requires authentication for list, disconnect, and deletion", async () => {
    const { app, db } = await setup();
    for (const [method, url] of [["GET", "/discovery/connections"], ["DELETE", `/discovery/connections/${connectionId}`], ["DELETE", "/account"]] as const)
      expect((await app.inject({ method, url })).statusCode).toBe(401);
    expect(db.user.delete).not.toHaveBeenCalled();
  });
  it("queries only the user's active connection metadata", async () => {
    const { app, db } = await setup();
    expect((await app.inject({ method: "GET", url: "/discovery/connections", headers })).statusCode).toBe(200);
    expect(db.institutionConnection.findMany).toHaveBeenCalledWith({ where: { userId, status: "active" }, select: { id: true, institutionName: true, status: true }, orderBy: { createdAt: "asc" } });
  });
  it("rejects a connection outside the user's ownership", async () => {
    const { app, db } = await setup(); const remove = vi.spyOn(PlaidClient.prototype, "removeItem").mockResolvedValue();
    expect((await app.inject({ method: "DELETE", url: `/discovery/connections/${connectionId}`, headers })).statusCode).toBe(404);
    expect(db.institutionConnection.findFirst).toHaveBeenCalledWith({ where: { id: connectionId, userId } });
    expect(remove).not.toHaveBeenCalled();
  });
  it("revokes bank access before deleting a connection", async () => {
    const { app, db } = await setup();
    db.institutionConnection.findFirst.mockResolvedValue({ id: connectionId, encryptedAccessToken: encryptToken("test-access", config.DATA_ENCRYPTION_KEY!) });
    const remove = vi.spyOn(PlaidClient.prototype, "removeItem").mockResolvedValue();
    expect((await app.inject({ method: "DELETE", url: `/discovery/connections/${connectionId}`, headers })).statusCode).toBe(204);
    expect(remove).toHaveBeenCalledWith("test-access");
    expect(remove.mock.invocationCallOrder[0]!).toBeLessThan(db.institutionConnection.deleteMany.mock.invocationCallOrder[0]!);
  });
  it("requires fresh Apple confirmation", async () => {
    const { app, db } = await setup();
    expect((await app.inject({ method: "DELETE", url: "/account", headers, payload: {} })).statusCode).toBe(400);
    expect(db.user.delete).not.toHaveBeenCalled();
  });
  it("rejects a different Apple account", async () => {
    const { app, db } = await setup(); vi.mocked(app.verifyAppleToken).mockResolvedValue({ subject: "another-user" });
    expect((await app.inject({ method: "DELETE", url: "/account", headers, payload })).statusCode).toBe(403);
    expect(revokeAppleAuthorization).not.toHaveBeenCalled(); expect(db.user.delete).not.toHaveBeenCalled();
  });
  it("retains the account on Apple revocation failure", async () => {
    const { app, db } = await setup(); vi.mocked(revokeAppleAuthorization).mockRejectedValue(new AppError("APPLE_REVOCATION_FAILED", "Retry", 502));
    expect((await app.inject({ method: "DELETE", url: "/account", headers, payload })).statusCode).toBe(502);
    expect(db.user.delete).not.toHaveBeenCalled();
  });
  it("retains the account and connection on bank revocation failure", async () => {
    const { app, db } = await setup();
    db.institutionConnection.findMany.mockResolvedValue([{ id: connectionId, encryptedAccessToken: encryptToken("test-access", config.DATA_ENCRYPTION_KEY!) }]);
    vi.spyOn(PlaidClient.prototype, "removeItem").mockRejectedValue(new AppError("UNAVAILABLE", "Retry", 502));
    expect((await app.inject({ method: "DELETE", url: "/account", headers, payload })).statusCode).toBe(502);
    expect(db.institutionConnection.deleteMany).not.toHaveBeenCalled(); expect(db.user.delete).not.toHaveBeenCalled();
  });
  it("revokes Apple access and removes household PII before the account", async () => {
    const { app, db } = await setup();
    expect((await app.inject({ method: "DELETE", url: "/account", headers, payload })).statusCode).toBe(204);
    expect(revokeAppleAuthorization).toHaveBeenCalledWith(config, "fresh-code", "apple-owner", app.verifyAppleToken);
    expect(db.householdMember.deleteMany).toHaveBeenCalledWith({ where: { userId } });
    expect(db.user.delete).toHaveBeenCalledWith({ where: { id: userId } });
    expect(vi.mocked(revokeAppleAuthorization).mock.invocationCallOrder[0]!).toBeLessThan(db.user.delete.mock.invocationCallOrder[0]!);
  });
});
