export type OptimizationSubscription = {
  id: string; merchant: string; category: string; monthlyCents: number; valueScore: number;
  usage: "high" | "medium" | "low" | "unknown"; isImportant?: boolean;
  householdOwnerId?: string; eligibleFamilyMonthlyCents?: number;
};
export type Recommendation = {
  type: "cancel" | "family_plan" | "duplicate_category";
  subscriptionIds: string[]; estimatedMonthlySavingsCents: number; estimatedAnnualSavingsCents: number;
  confidence: number; reasonCodes: string[]; explanation: string; effortMinutes: number;
};

export function optimizeSubscriptions(subscriptions: OptimizationSubscription[]): Recommendation[] {
  const recommendations: Recommendation[] = [];
  const alreadyRecommended = new Set<string>();

  const merchantGroups = Map.groupBy(subscriptions, (item) => normalizedMerchant(item.merchant));
  for (const [merchantKey, matches] of merchantGroups) {
    if (!merchantKey || matches.length < 2) continue;
    const candidate = reviewCandidate(matches);
    if (!candidate) continue;
    recommendations.push({
      type: "duplicate_category",
      subscriptionIds: [candidate.id, ...matches.filter((item) => item.id !== candidate.id).map((item) => item.id)],
      estimatedMonthlySavingsCents: candidate.monthlyCents,
      estimatedAnnualSavingsCents: candidate.monthlyCents * 12,
      confidence: 0.92,
      reasonCodes: ["exact_merchant_duplicate"],
      explanation: `${matches.length} saved entries appear to be ${candidate.merchant}. Compare account and plan details before removing one.`,
      effortMinutes: 4
    });
    alreadyRecommended.add(candidate.id);
  }

  for (const item of subscriptions) {
    if (!alreadyRecommended.has(item.id) && !item.isImportant && item.valueScore < 40 && item.usage === "low") {
      recommendations.push({
      type: "cancel", subscriptionIds: [item.id], estimatedMonthlySavingsCents: item.monthlyCents,
      estimatedAnnualSavingsCents: item.monthlyCents * 12, confidence: 0.9,
      reasonCodes: ["low_usage", "poor_value_score"], explanation: `${item.merchant} has low reported use and a poor Value Score.`, effortMinutes: 3
      });
      alreadyRecommended.add(item.id);
    }
  }
  const categories = Map.groupBy(subscriptions, (item) => item.category);
  for (const [category, matches] of categories) {
    if (matches.length < 2 || new Set(matches.map((item) => normalizedMerchant(item.merchant))).size < 2) continue;
    const candidate = reviewCandidate(matches);
    if (!candidate || alreadyRecommended.has(candidate.id) || candidate.valueScore >= 50 || candidate.usage === "high") continue;
    recommendations.push({ type: "duplicate_category", subscriptionIds: [candidate.id, ...matches.filter((item) => item.id !== candidate.id).map((item) => item.id)], estimatedMonthlySavingsCents: candidate.monthlyCents,
      estimatedAnnualSavingsCents: candidate.monthlyCents * 12, confidence: 0.72, reasonCodes: ["category_overlap"],
      explanation: `Review overlapping ${category} subscriptions before removing one.`, effortMinutes: 5 });
    alreadyRecommended.add(candidate.id);
  }
  return recommendations.sort((a, b) => b.estimatedAnnualSavingsCents - a.estimatedAnnualSavingsCents || b.confidence - a.confidence);
}

function reviewCandidate(items: OptimizationSubscription[]) {
  return items
    .filter((item) => !item.isImportant)
    .sort((a, b) => a.valueScore - b.valueScore || b.monthlyCents - a.monthlyCents)[0];
}

function normalizedMerchant(value: string) {
  const planWords = new Set(["premium", "standard", "basic", "plus", "pro", "monthly", "annual", "yearly", "subscription", "plan"]);
  return value.toLowerCase().split(/[^a-z0-9]+/).filter((part) => part && !planWords.has(part)).join(" ");
}
