export type ValueScoreInput = {
  monthlyCents: number;
  usage: "high" | "medium" | "low" | "unknown";
  householdUsers: number;
  isDuplicate: boolean;
  hasCheaperAlternative: boolean;
  isImportant: boolean;
  priceIncreasePercent: number;
  isTrial: boolean;
};

export type ValueScoreResult = { score: number; label: string; reasonCodes: string[] };

export function calculateValueScore(input: ValueScoreInput): ValueScoreResult {
  let score = 50;
  const reasons: string[] = [];
  const usage = { high: 30, medium: 12, low: -22, unknown: 0 }[input.usage];
  score += usage;
  reasons.push(`usage_${input.usage}`);
  if (input.householdUsers > 1) { score += Math.min(15, (input.householdUsers - 1) * 6); reasons.push("shared_household_usage"); }
  if (input.isDuplicate) { score -= 25; reasons.push("duplicate_service"); }
  if (input.hasCheaperAlternative) { score -= 10; reasons.push("cheaper_alternative"); }
  if (input.isImportant) { score += 15; reasons.push("user_marked_important"); }
  if (input.priceIncreasePercent >= 10) { score -= 8; reasons.push("recent_charge_higher"); }
  if (input.isTrial) { score -= 4; reasons.push("trial_requires_review"); }
  if (input.monthlyCents >= 5000 && input.usage !== "high") { score -= 8; reasons.push("high_cost_for_usage"); }
  score = Math.max(0, Math.min(100, score));
  const label = score >= 80 ? "Great Value" : score >= 60 ? "Good Value" : score >= 40 ? "Review" : score >= 20 ? "Poor Value" : "Likely Waste";
  return { score, label, reasonCodes: reasons };
}
