import { describe, expect, it } from "vitest";
import { calculateValueScore } from "../src/domain/value-score.js";

describe("Value Score", () => {
  it("explains low-use duplicate services", () => {
    const result = calculateValueScore({ monthlyCents: 5999, usage: "low", householdUsers: 1, isDuplicate: true, hasCheaperAlternative: true, isImportant: false, priceIncreasePercent: 12, isTrial: false });
    expect(result.score).toBeLessThan(20);
    expect(result.reasonCodes).toContain("duplicate_service");
    expect(result.label).toBe("Likely Waste");
  });
  it("respects user importance", () => {
    const result = calculateValueScore({ monthlyCents: 1000, usage: "high", householdUsers: 2, isDuplicate: false, hasCheaperAlternative: false, isImportant: true, priceIncreasePercent: 0, isTrial: false });
    expect(result.score).toBeGreaterThanOrEqual(80);
  });
});
