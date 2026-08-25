export type Money = Readonly<{ cents: number; currency: "USD" }>;
export const usd = (cents: number): Money => {
  if (!Number.isSafeInteger(cents)) throw new TypeError("Money must use integer cents");
  return { cents, currency: "USD" };
};
export const annualize = (cents: number, frequency: string): number => {
  const multiplier: Record<string, number> = { weekly: 52, biweekly: 26, monthly: 12, quarterly: 4, semiannual: 2, yearly: 1 };
  return Math.round(cents * (multiplier[frequency] ?? 12));
};
export const monthlyEquivalent = (cents: number, frequency: string): number => Math.round(annualize(cents, frequency) / 12);
