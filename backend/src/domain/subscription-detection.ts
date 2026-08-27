import { normalizeMerchant } from "./merchant-resolver.js";

export type DiscoveryFrequency = "weekly" | "biweekly" | "monthly" | "quarterly" | "semiannual" | "yearly" | "irregular";
export type DetectionTransaction = {
  id: string;
  name: string;
  merchantName?: string | null;
  amount: number;
  date: string;
  category?: string | null;
  accountMask?: string | null;
};
export type DetectedCandidate = {
  id: string;
  rawMerchantName: string;
  displayName: string;
  amountCents: number;
  currency: "USD";
  frequency: DiscoveryFrequency;
  nextExpectedCharge: string | null;
  category: string;
  confidence: number;
  needsReview: boolean;
  paymentMethod: string | null;
  evidenceCount: number;
  source: "plaid";
};

const day = 86_400_000;
const frequencyForDays = (days: number): DiscoveryFrequency => {
  if (days >= 5 && days <= 10) return "weekly";
  if (days >= 11 && days <= 18) return "biweekly";
  if (days >= 24 && days <= 38) return "monthly";
  if (days >= 75 && days <= 105) return "quarterly";
  if (days >= 150 && days <= 215) return "semiannual";
  if (days >= 330 && days <= 400) return "yearly";
  return "irregular";
};

export function detectRecurringTransactions(transactions: DetectionTransaction[]): DetectedCandidate[] {
  const expenses = transactions.filter((item) => item.amount > 0 && !Number.isNaN(Date.parse(item.date)));
  const groups = Map.groupBy(expenses, (item) => normalizeMerchant(item.merchantName || item.name).canonicalName.toLowerCase());
  const candidates: DetectedCandidate[] = [];
  for (const matches of groups.values()) {
    if (matches.length < 2) continue;
    const ordered = [...matches].sort((a, b) => Date.parse(a.date) - Date.parse(b.date));
    const gaps = ordered.slice(1).map((item, index) => (Date.parse(item.date) - Date.parse(ordered[index]!.date)) / day).sort((a, b) => a - b);
    const medianGap = gaps[Math.floor(gaps.length / 2)];
    if (medianGap === undefined) continue;
    const frequency = frequencyForDays(medianGap);
    if (frequency === "irregular") continue;
    const amounts = ordered.map((item) => item.amount).sort((a, b) => a - b);
    const medianAmount = amounts[Math.floor(amounts.length / 2)];
    if (medianAmount === undefined) continue;
    const stableAmounts = amounts.filter((amount) => Math.abs(amount - medianAmount) <= Math.max(1, medianAmount * 0.2)).length / amounts.length;
    if (stableAmounts < 0.66) continue;
    const last = ordered.at(-1)!;
    const normalized = normalizeMerchant(last.merchantName || last.name);
    const nextDate = new Date(Date.parse(last.date) + medianGap * day).toISOString().slice(0, 10);
    const cadenceConfidence = Math.min(0.96, 0.58 + Math.min(matches.length, 6) * 0.06);
    candidates.push({
      id: `plaid:${last.id}`,
      rawMerchantName: last.name,
      displayName: normalized.canonicalName,
      amountCents: Math.round(medianAmount * 100),
      currency: "USD",
      frequency,
      nextExpectedCharge: nextDate,
      category: categoryName(last.category),
      confidence: Math.min(cadenceConfidence, normalized.needsReview ? 0.59 : 0.94),
      needsReview: normalized.needsReview,
      paymentMethod: last.accountMask ? `Account •••• ${last.accountMask}` : null,
      evidenceCount: matches.length,
      source: "plaid"
    });
  }
  return candidates.sort((a, b) => b.amountCents - a.amountCents);
}

export function candidateFromPlaidStream(stream: PlaidRecurringStream): DetectedCandidate | null {
  if (!stream.is_active || !stream.last_amount?.amount || stream.last_amount.amount <= 0) return null;
  const normalized = normalizeMerchant(stream.merchant_name || stream.description);
  const frequency = plaidFrequency(stream.frequency);
  return {
    id: `plaid:${stream.stream_id}`,
    rawMerchantName: stream.description,
    displayName: normalized.canonicalName,
    amountCents: Math.round(stream.last_amount.amount * 100),
    currency: "USD",
    frequency,
    nextExpectedCharge: stream.predicted_next_date ?? null,
    category: categoryName(stream.personal_finance_category?.primary),
    confidence: Math.min(stream.status === "MATURE" ? 0.94 : 0.76, normalized.needsReview ? 0.59 : 0.94),
    needsReview: normalized.needsReview,
    paymentMethod: null,
    evidenceCount: stream.transaction_ids.length,
    source: "plaid"
  };
}

export type PlaidRecurringStream = {
  stream_id: string; description: string; merchant_name?: string | null; predicted_next_date?: string | null;
  frequency: string; transaction_ids: string[]; last_amount?: { amount: number } | null; is_active: boolean; status: string;
  personal_finance_category?: { primary?: string | null } | null;
};

function plaidFrequency(value: string): DiscoveryFrequency {
  switch (value) {
    case "WEEKLY": return "weekly";
    case "BIWEEKLY": case "SEMI_MONTHLY": return "biweekly";
    case "MONTHLY": return "monthly";
    case "QUARTERLY": return "quarterly";
    case "SEMI_ANNUALLY": return "semiannual";
    case "ANNUALLY": return "yearly";
    default: return "irregular";
  }
}

function categoryName(value?: string | null): string {
  const raw = (value || "").toUpperCase();
  if (raw.includes("ENTERTAINMENT")) return "Streaming";
  if (raw.includes("SOFTWARE") || raw.includes("GENERAL_SERVICES")) return "Productivity";
  if (raw.includes("FITNESS") || raw.includes("GYM")) return "Fitness";
  return "Other";
}
