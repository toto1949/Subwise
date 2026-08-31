import Fastify from "fastify";
import { describe, expect, it } from "vitest";
import legalRoutes, { privacyPolicyLastUpdated } from "../src/routes/legal.js";

describe("privacy policy", () => {
  it("serves the complete public policy without authentication", async () => {
    const app = Fastify();
    await app.register(legalRoutes);

    const response = await app.inject({ method: "GET", url: "/privacy-policy" });

    expect(response.statusCode).toBe(200);
    expect(response.headers["content-type"]).toContain("text/html");
    expect(response.headers["cache-control"]).toContain("public");
    expect(response.body).toContain("Privacy Policy");
    expect(response.body).toContain(privacyPolicyLastUpdated);
    expect(response.body).toContain("Bank and card connections through Plaid");
    expect(response.body).toContain("Savings Agent conversations");
    expect(response.body).toContain("Retention and deletion");
    await app.close();
  });

  it("keeps the short privacy URL as a permanent redirect", async () => {
    const app = Fastify();
    await app.register(legalRoutes);

    const response = await app.inject({ method: "GET", url: "/privacy" });

    expect(response.statusCode).toBe(308);
    expect(response.headers.location).toBe("/privacy-policy");
    await app.close();
  });
});
