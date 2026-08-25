import { PrismaClient } from "@prisma/client";
const db = new PrismaClient();

async function seed() {
  const user = await db.user.upsert({ where: { appleSubject: "development-user" }, update: {}, create: { appleSubject: "development-user", email: "developer@example.test", displayName: "Demo User" } });
  const merchantSeed: Array<[string, string]> = [
    ["Netflix", "Streaming"], ["Spotify", "Music"], ["Adobe", "Productivity"], ["iCloud+", "Cloud"], ["ChatGPT", "AI"], ["Canva", "Productivity"]
  ];
  const merchants = await Promise.all(merchantSeed.map(([canonicalName, category]) => db.merchant.upsert({ where: { canonicalName }, update: {}, create: { canonicalName, category } })));
  const byName = new Map(merchants.map((merchant) => [merchant.canonicalName, merchant]));
  const examples = [
    { name: "Netflix", plan: "Premium", cents: 2499, score: 78, usage: "high" },
    { name: "Spotify", plan: "Individual", cents: 1199, score: 84, usage: "high" },
    { name: "Adobe", plan: "Creative Cloud", cents: 5999, score: 31, usage: "low" },
    { name: "iCloud+", plan: "2 TB", cents: 999, score: 62, usage: "medium" },
    { name: "ChatGPT", plan: "Plus", cents: 2000, score: 88, usage: "high" }
  ];
  for (const item of examples) {
    const exists = await db.subscription.findFirst({ where: { userId: user.id, displayName: item.name } });
    if (!exists) await db.subscription.create({ data: { userId: user.id, merchantId: byName.get(item.name)?.id, rawMerchantName: item.name, displayName: item.name, planName: item.plan, amountCents: item.cents, currency: "USD", frequency: "MONTHLY", status: "ACTIVE", category: byName.get(item.name)?.category ?? "Other", valueScore: item.score, usage: item.usage } });
  }
}

seed().finally(() => db.$disconnect());
