import { describe, expect, it } from "vitest";
import { annualize, monthlyEquivalent, usd } from "../src/lib/money.js";

describe("money", () => {
  it("uses integer minor units", () => { expect(usd(1199)).toEqual({ cents: 1199, currency: "USD" }); });
  it("normalizes frequencies without floating point drift", () => {
    expect(annualize(1199, "monthly")).toBe(14388);
    expect(monthlyEquivalent(12000, "yearly")).toBe(1000);
  });
  it("rejects fractional cents", () => { expect(() => usd(10.2)).toThrow(); });
});
