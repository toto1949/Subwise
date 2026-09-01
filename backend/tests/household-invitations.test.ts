import { describe, expect, it } from "vitest";
import { AppError } from "../src/lib/errors.js";
import { createHouseholdInviteToken, escapeHTML, verifyHouseholdInviteToken } from "../src/services/household-invitations.js";

describe("household invitation links", () => {
  const secret = "a-production-length-secret-with-more-than-32-characters";
  const memberId = "45ab73cc-2309-4ad0-a2d8-17493a3fdcf1";
  const now = Date.UTC(2026, 8, 1, 12, 0, 0);

  it("signs a seven-day bearer link that cannot be altered", () => {
    const token = createHouseholdInviteToken(memberId, secret, now);
    const payload = verifyHouseholdInviteToken(token, secret, now + 1_000);
    expect(payload.memberId).toBe(memberId);
    expect(payload.expiresAt).toBe(Math.floor(now / 1_000) + 7 * 24 * 60 * 60);
    expect(() => verifyHouseholdInviteToken(token.replace(memberId, "55ab73cc-2309-4ad0-a2d8-17493a3fdcf1"), secret, now)).toThrow(AppError);
  });

  it("rejects expired invitations", () => {
    const token = createHouseholdInviteToken(memberId, secret, now);
    expect(() => verifyHouseholdInviteToken(token, secret, now + 8 * 24 * 60 * 60 * 1_000)).toThrow("expired");
  });

  it("escapes user-controlled email content", () => {
    expect(escapeHTML(`<script>alert("x")</script>`)).toBe("&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;");
  });
});
