import { describe, expect, it } from "vitest";
import { candidateFromPlaidStream, detectRecurringTransactions } from "../src/domain/subscription-detection.js";

describe("subscription detection", () => {
  it("detects stable monthly charges and predicts the next date", () => {
    const result = detectRecurringTransactions([
      { id: "1", name: "NETFLIX.COM 8661234567", amount: 22.99, date: "2026-05-18" },
      { id: "2", name: "NETFLIX.COM 8661234567", amount: 22.99, date: "2026-06-18" },
      { id: "3", name: "NETFLIX.COM 8661234567", amount: 22.99, date: "2026-07-18" }
    ]);
    expect(result).toHaveLength(1);
    expect(result[0]).toMatchObject({ displayName: "Netflix", frequency: "monthly", amountCents: 2299, needsReview: false });
    expect(result[0]?.nextExpectedCharge).toBe("2026-08-18");
  });

  it("does not guess ambiguous Apple billing", () => {
    const candidate = candidateFromPlaidStream({
      stream_id: "apple", description: "APPLE.COM/BILL", merchant_name: "APPLE.COM/BILL", predicted_next_date: "2026-09-01",
      frequency: "MONTHLY", transaction_ids: ["1", "2", "3"], last_amount: { amount: 9.99 }, is_active: true, status: "MATURE"
    });
    expect(candidate).toMatchObject({ displayName: "Apple purchase", needsReview: true });
    expect(candidate!.confidence).toBeLessThan(0.6);
  });

  it("rejects one-off and unstable charges", () => {
    expect(detectRecurringTransactions([{ id: "1", name: "Shop", amount: 10, date: "2026-05-01" }])).toEqual([]);
    expect(detectRecurringTransactions([
      { id: "1", name: "Shop", amount: 10, date: "2026-05-01" },
      { id: "2", name: "Shop", amount: 90, date: "2026-06-01" },
      { id: "3", name: "Shop", amount: 20, date: "2026-07-01" }
    ])).toEqual([]);
  });
});
