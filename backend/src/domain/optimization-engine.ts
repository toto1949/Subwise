export type OptimizationSubscription = {
  id: string; merchant: string; category: string; monthlyCents: number; valueScore: number;
  usage: "high" | "medium" | "low" | "unknown"; householdOwnerId?: string; eligibleFamilyMonthlyCents?: number;
};
export type Recommendation = {
  type: "cancel" | "family_plan" | "duplicate_category";
  subscriptionIds: string[]; estimatedMonthlySavingsCents: number; estimatedAnnualSavingsCents: number;
  confidence: number; reasonCodes: string[]; explanation: string; effortMinutes: number;
};

export function optimizeSubscriptions(subscriptions: OptimizationSubscription[]): Recommendation[] {
  const recommendations: Recommendation[] = [];
  for (const item of subscriptions) {
    if (item.valueScore < 40 && item.usage === "low") recommendations.push({
      type: "cancel", subscriptionIds: [item.id], estimatedMonthlySavingsCents: item.monthlyCents,
      estimatedAnnualSavingsCents: item.monthlyCents * 12, confidence: 0.9,
      reasonCodes: ["low_usage", "poor_value_score"], explanation: `${item.merchant} has low reported use and a poor Value Score.`, effortMinutes: 3
    });
  }
  const categories = Map.groupBy(subscriptions, (item) => item.category);
  const alreadyRecommended = new Set(recommendations.flatMap((item) => item.subscriptionIds));
  for (const [category, matches] of categories) {
    if (matches.length < 2) continue;
    const sorted = [...matches].sort((a, b) => b.valueScore - a.valueScore);
    const candidate = sorted.at(-1)!;
    if (alreadyRecommended.has(candidate.id)) continue;
    recommendations.push({ type: "duplicate_category", subscriptionIds: matches.map((item) => item.id), estimatedMonthlySavingsCents: candidate.monthlyCents,
      estimatedAnnualSavingsCents: candidate.monthlyCents * 12, confidence: 0.72, reasonCodes: ["category_overlap"],
      explanation: `Review overlapping ${category} subscriptions before removing one.`, effortMinutes: 5 });
    matches.forEach((item) => alreadyRecommended.add(item.id));
  }
  return recommendations.sort((a, b) => b.estimatedAnnualSavingsCents - a.estimatedAnnualSavingsCents || b.confidence - a.confidence);
}
