import { describe, expect, it } from "vitest";
import { normalizeMerchant } from "../src/domain/merchant-resolver.js";

describe("MerchantResolver", () => {
  it.each(["NETFLIX.COM 4087249160", "Netflix.com", "NETFLIX"])("normalizes %s", (raw) => {
    expect(normalizeMerchant(raw).canonicalName).toBe("Netflix");
  });
  it("keeps unknown merchants for user confirmation", () => { expect(normalizeMerchant("Local App LLC").confidence).toBeLessThan(0.5); });
});
