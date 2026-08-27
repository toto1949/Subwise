export type OptimizationSubscription = {
  id: string; merchant: string; category: string; monthlyCents: number; valueScore: number;
  usage: "high" | "medium" | "low" | "unknown"; isImportant?: boolean;
  householdOwnerId?: string; eligibleFamilyMonthlyCents?: number;
  currentPlanName?: string | null;
  currentFrequency?: string;
  previousMonthlyCents?: number;
  householdSize?: number;
  plans?: VerifiedPlan[];
};
export type VerifiedPlan = {
  name: string; monthlyCents: number; frequency: string; planType: string; householdSize?: number | null;
  eligibilityType?: string | null; sourceUrl: string; verifiedAt: Date;
};
export type Recommendation = {
  type: "cancel" | "family_plan" | "duplicate_category" | "cheaper_plan" | "annual_plan" | "student_plan" | "price_increase";
  subscriptionIds: string[]; estimatedMonthlySavingsCents: number; estimatedAnnualSavingsCents: number;
  confidence: number; reasonCodes: string[]; explanation: string; effortMinutes: number;
};

export function optimizeSubscriptions(subscriptions: OptimizationSubscription[]): Recommendation[] {
  const recommendations: Recommendation[] = [];
  const alreadyRecommended = new Set<string>();

  for (const item of subscriptions) {
    const plans = (item.plans ?? []).filter((plan) => plan.verifiedAt.getTime() >= Date.now() - 45 * 86_400_000);
    const nonEligibilityPlans = plans.filter((plan) => !plan.eligibilityType);
    const annual = nonEligibilityPlans
      .filter((plan) => plan.frequency === "yearly" && plan.monthlyCents < item.monthlyCents)
      .sort((a, b) => a.monthlyCents - b.monthlyCents)[0];
    const cheaper = nonEligibilityPlans
      .filter((plan) => plan.monthlyCents < item.monthlyCents && plan !== annual && (!plan.householdSize || plan.householdSize <= 1))
      .sort((a, b) => a.monthlyCents - b.monthlyCents)[0];
    const family = nonEligibilityPlans
      .filter((plan) => (plan.householdSize ?? 0) > 1 && (item.householdSize ?? 1) > 1 && plan.monthlyCents < item.monthlyCents)
      .sort((a, b) => a.monthlyCents - b.monthlyCents)[0];
    const student = plans
      .filter((plan) => plan.eligibilityType?.toLowerCase() === "student" && plan.monthlyCents < item.monthlyCents)
      .sort((a, b) => a.monthlyCents - b.monthlyCents)[0];

    if (annual && item.currentFrequency !== "yearly") recommendations.push(planRecommendation(item, annual, "annual_plan", 0.9, ["verified_provider_price", "annual_billing_option"], `Compare ${annual.name} annual billing. Provider pricing was verified recently; confirm included features before switching.`));
    else if (cheaper) recommendations.push(planRecommendation(item, cheaper, "cheaper_plan", 0.82, ["verified_provider_price", "lower_priced_plan"], `A lower-priced ${cheaper.name} option is listed by the provider. Compare features before deciding.`));
    if (family) recommendations.push(planRecommendation(item, family, "family_plan", 0.72, ["verified_provider_price", "household_members_present"], `${family.name} may reduce household cost. Confirm sharing rules and member eligibility first.`));
    if (student) recommendations.push(planRecommendation(item, student, "student_plan", 0.55, ["verified_provider_price", "eligibility_unverified"], `${student.name} has student pricing. SubWise has not verified your eligibility; check with the provider.`));
    if (item.previousMonthlyCents && item.previousMonthlyCents < item.monthlyCents) {
      const increase = item.monthlyCents - item.previousMonthlyCents;
      recommendations.push({ type: "price_increase", subscriptionIds: [item.id], estimatedMonthlySavingsCents: increase, estimatedAnnualSavingsCents: increase * 12, confidence: 0.96,
        reasonCodes: ["confirmed_price_observation"], explanation: `${item.merchant} increased from ${formatMoney(item.previousMonthlyCents)} to ${formatMoney(item.monthlyCents)} per month. Explore verified plan options.`, effortMinutes: 4 });
    }
  }

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

function planRecommendation(item: OptimizationSubscription, plan: VerifiedPlan, type: Recommendation["type"], confidence: number, reasonCodes: string[], explanation: string): Recommendation {
  const savings = Math.max(0, item.monthlyCents - plan.monthlyCents);
  return { type, subscriptionIds: [item.id], estimatedMonthlySavingsCents: savings, estimatedAnnualSavingsCents: savings * 12, confidence, reasonCodes: [...reasonCodes, `source:${plan.sourceUrl}`], explanation, effortMinutes: 5 };
}

function formatMoney(cents: number) { return `$${(cents / 100).toFixed(2)}`; }

function reviewCandidate(items: OptimizationSubscription[]) {
  return items
    .filter((item) => !item.isImportant)
    .sort((a, b) => a.valueScore - b.valueScore || b.monthlyCents - a.monthlyCents)[0];
}

function normalizedMerchant(value: string) {
  const planWords = new Set(["premium", "standard", "basic", "plus", "pro", "monthly", "annual", "yearly", "subscription", "plan"]);
  return value.toLowerCase().split(/[^a-z0-9]+/).filter((part) => part && !planWords.has(part)).join(" ");
}
