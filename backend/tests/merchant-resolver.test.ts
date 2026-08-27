import { describe, expect, it } from "vitest";
import { normalizeMerchant } from "../src/domain/merchant-resolver.js";

describe("MerchantResolver", () => {
  it.each(["NETFLIX.COM 4087249160", "Netflix.com", "NETFLIX"])("normalizes %s", (raw) => {
    expect(normalizeMerchant(raw).canonicalName).toBe("Netflix");
  });
  it("keeps unknown merchants for user confirmation", () => { expect(normalizeMerchant("Local App LLC").confidence).toBeLessThan(0.5); });
  it("never guesses an ambiguous Apple bill", () => {
    expect(normalizeMerchant("APPLE.COM/BILL 866-712-7753")).toMatchObject({ canonicalName: "Apple purchase", needsReview: true });
  });
});
