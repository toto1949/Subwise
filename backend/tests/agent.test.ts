import { describe, expect, it } from "vitest";
import { verifiedSavingsFor } from "../src/routes/agent.js";

describe("Savings Agent verified calculations", () => {
  const keepID = "10000000-0000-0000-0000-000000000001";
  const reviewID = "10000000-0000-0000-0000-000000000002";
  const context = [
    { id: keepID, merchant: "Keep", monthlyEquivalentCents: 2_000, usage: "high" as const, valueScore: 90, userPriority: "keep" as const, category: "Streaming", status: "Active", allowedActions: ["keep", "review"] },
    { id: reviewID, merchant: "Review", monthlyEquivalentCents: 1_499, usage: "low" as const, valueScore: 20, userPriority: "normal" as const, category: "Productivity", status: "Needs review", allowedActions: ["keep", "review", "cancel"] }
  ];

  it("computes savings from saved prices and ignores duplicate IDs", () => {
    expect(verifiedSavingsFor([reviewID, reviewID], context)).toBe(1_499);
  });

  it("never counts a subscription marked important to keep", () => {
    expect(verifiedSavingsFor([keepID, reviewID], context)).toBe(1_499);
  });

  it("ignores model-invented subscription IDs", () => {
    expect(verifiedSavingsFor(["10000000-0000-0000-0000-000000000099"], context)).toBe(0);
  });
});
