import { describe, expect, it } from "vitest";
import { optimizeSubscriptions } from "../src/domain/optimization-engine.js";

describe("OptimizationEngine", () => {
  it("ranks verified arithmetic by annual savings", () => {
    const results = optimizeSubscriptions([
      { id: "adobe", merchant: "Adobe", category: "productivity", monthlyCents: 5999, valueScore: 25, usage: "low" },
      { id: "video-a", merchant: "Video A", category: "streaming", monthlyCents: 1000, valueScore: 80, usage: "high" },
      { id: "video-b", merchant: "Video B", category: "streaming", monthlyCents: 1500, valueScore: 45, usage: "medium" }
    ]);
    expect(results[0]?.type).toBe("cancel");
    expect(results[0]?.estimatedAnnualSavingsCents).toBe(71988);
    expect(results.some((item) => item.type === "duplicate_category")).toBe(true);
  });

  it("does not count one subscription in both cancel and overlap savings", () => {
    const results = optimizeSubscriptions([
      { id: "adobe", merchant: "Adobe", category: "productivity", monthlyCents: 5999, valueScore: 25, usage: "low" },
      { id: "canva", merchant: "Canva", category: "productivity", monthlyCents: 1499, valueScore: 45, usage: "medium" }
    ]);
    expect(results).toHaveLength(1);
    expect(results[0]?.subscriptionIds).toEqual(["adobe"]);
  });

  it("detects exact merchant duplicates and protects important entries", () => {
    const results = optimizeSubscriptions([
      { id: "netflix-main", merchant: "Netflix Premium", category: "streaming", monthlyCents: 2499, valueScore: 80, usage: "high", isImportant: true },
      { id: "netflix-extra", merchant: "Netflix Basic", category: "streaming", monthlyCents: 1199, valueScore: 45, usage: "unknown" }
    ]);
    expect(results).toHaveLength(1);
    expect(results[0]?.reasonCodes).toContain("exact_merchant_duplicate");
    expect(results[0]?.subscriptionIds[0]).toBe("netflix-extra");
    expect(results[0]?.estimatedMonthlySavingsCents).toBe(1199);
  });
});
