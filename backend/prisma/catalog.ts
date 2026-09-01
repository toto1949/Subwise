import { PrismaClient, type BillingFrequency } from "@prisma/client";

const db = new PrismaClient();
const verifiedAt = new Date("2026-09-01T12:00:00.000Z");

type CatalogPlan = {
  merchant: string;
  category: string;
  name: string;
  priceCents: number;
  frequency: BillingFrequency;
  planType: string;
  householdSize?: number;
  eligibilityType?: string;
  sourceUrl: string;
};

const plans: CatalogPlan[] = [
  { merchant: "Spotify", category: "Music", name: "Premium Individual", priceCents: 1299, frequency: "MONTHLY", planType: "individual", sourceUrl: "https://www.spotify.com/us/premium/" },
  { merchant: "Spotify", category: "Music", name: "Premium Student", priceCents: 699, frequency: "MONTHLY", planType: "student", eligibilityType: "student", sourceUrl: "https://www.spotify.com/us/premium/" },
  { merchant: "Spotify", category: "Music", name: "Premium Duo", priceCents: 1899, frequency: "MONTHLY", planType: "household", householdSize: 2, sourceUrl: "https://www.spotify.com/us/premium/" },
  { merchant: "Spotify", category: "Music", name: "Premium Family", priceCents: 2199, frequency: "MONTHLY", planType: "household", householdSize: 6, sourceUrl: "https://www.spotify.com/us/premium/" },
  { merchant: "Apple Music", category: "Music", name: "Individual", priceCents: 1199, frequency: "MONTHLY", planType: "individual", sourceUrl: "https://www.apple.com/apple-music/" },
  { merchant: "Apple Music", category: "Music", name: "Student", priceCents: 699, frequency: "MONTHLY", planType: "student", eligibilityType: "student", sourceUrl: "https://www.apple.com/apple-music/" },
  { merchant: "Apple Music", category: "Music", name: "Family", priceCents: 1999, frequency: "MONTHLY", planType: "household", householdSize: 6, sourceUrl: "https://www.apple.com/apple-music/" }
];

async function upsertPlan(value: CatalogPlan) {
  const merchant = await db.merchant.upsert({
    where: { canonicalName: value.merchant },
    update: { category: value.category, active: true },
    create: { canonicalName: value.merchant, category: value.category }
  });
  const existing = await db.merchantPlan.findFirst({
    where: { merchantId: merchant.id, name: value.name, frequency: value.frequency }
  });
  const data = {
    merchantId: merchant.id, name: value.name, priceCents: value.priceCents, frequency: value.frequency,
    currency: "USD", planType: value.planType, householdSize: value.householdSize,
    eligibilityType: value.eligibilityType, sourceUrl: value.sourceUrl, verifiedAt
  };
  if (existing) await db.merchantPlan.update({ where: { id: existing.id }, data });
  else await db.merchantPlan.create({ data });
}

async function main() {
  for (const plan of plans) await upsertPlan(plan);
  const spotify = await db.merchant.findUniqueOrThrow({ where: { canonicalName: "Spotify" } });
  const appleMusic = await db.merchant.findUniqueOrThrow({ where: { canonicalName: "Apple Music" } });
  await db.merchantAlternative.upsert({
    where: { sourceMerchantId_alternativeMerchantId: { sourceMerchantId: spotify.id, alternativeMerchantId: appleMusic.id } },
    update: { rationale: "Both provide individual music-streaming plans, but libraries, discovery, audio features, and device fit differ." },
    create: {
      sourceMerchantId: spotify.id, alternativeMerchantId: appleMusic.id,
      rationale: "Both provide individual music-streaming plans, but libraries, discovery, audio features, and device fit differ."
    }
  });
  console.log(`Verified catalog updated: ${plans.length} plans, verified ${verifiedAt.toISOString()}`);
}

main().finally(() => db.$disconnect());
