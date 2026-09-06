import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { exportPKCS8, generateKeyPair } from "jose";
import { loadConfig } from "../src/config.js";
import { revokeAppleAuthorization } from "../src/services/apple-authorization.js";
let privateKey: string;
beforeAll(async () => { const keys = await generateKeyPair("ES256", { extractable: true }); privateKey = await exportPKCS8(keys.privateKey); });
afterEach(() => vi.unstubAllGlobals());
function config() { return loadConfig({ DATABASE_URL: "postgresql://localhost/test", ACCESS_TOKEN_SECRET: "x".repeat(32), APPLE_CLIENT_ID: "com.toto.Subwise", APPLE_TEAM_ID: "team", APPLE_KEY_ID: "key", APPLE_PRIVATE_KEY: privateKey }); }
describe("Apple deletion authorization", () => {
  it("exchanges the fresh code and revokes the resulting refresh token", async () => {
    const fetcher = vi.fn().mockResolvedValueOnce(Response.json({ refresh_token: "provider-token", id_token: "identity" })).mockResolvedValueOnce(new Response(null, { status: 200 }));
    vi.stubGlobal("fetch", fetcher);
    const verify = vi.fn().mockResolvedValue({ subject: "owner" });
    await revokeAppleAuthorization(config(), "fresh-code", "owner", verify);
    expect(verify).toHaveBeenCalledWith("identity");
    expect(fetcher.mock.calls[0]![0]).toBe("https://appleid.apple.com/auth/token");
    expect(fetcher.mock.calls[0]![1].body.get("code")).toBe("fresh-code");
    expect(fetcher.mock.calls[1]![0]).toBe("https://appleid.apple.com/auth/revoke");
    expect(fetcher.mock.calls[1]![1].body.get("token")).toBe("provider-token");
    expect(fetcher.mock.calls[1]![1].body.get("token_type_hint")).toBe("refresh_token");
  });
  it("does not revoke another Apple user's token", async () => {
    const fetcher = vi.fn().mockResolvedValue(Response.json({ refresh_token: "provider-token", id_token: "identity" })); vi.stubGlobal("fetch", fetcher);
    await expect(revokeAppleAuthorization(config(), "code", "owner", async () => ({ subject: "other" }))).rejects.toMatchObject({ statusCode: 403 });
    expect(fetcher).toHaveBeenCalledTimes(1);
  });
  it("reports a failed provider revocation", async () => {
    const fetcher = vi.fn().mockResolvedValueOnce(Response.json({ refresh_token: "provider-token", id_token: "identity" })).mockResolvedValueOnce(new Response(null, { status: 500 })); vi.stubGlobal("fetch", fetcher);
    await expect(revokeAppleAuthorization(config(), "code", "owner", async () => ({ subject: "owner" }))).rejects.toMatchObject({ code: "APPLE_REVOCATION_FAILED" });
  });
  it("fails before provider calls when the server key is missing", async () => {
    const fetcher = vi.fn(); vi.stubGlobal("fetch", fetcher);
    await expect(revokeAppleAuthorization({ ...config(), APPLE_PRIVATE_KEY: undefined }, "code", "owner", async () => ({ subject: "owner" }))).rejects.toMatchObject({ statusCode: 503 });
    expect(fetcher).not.toHaveBeenCalled();
  });
});
