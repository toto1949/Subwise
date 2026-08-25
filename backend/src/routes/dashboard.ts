import type { FastifyPluginAsync } from "fastify";
import { monthlyEquivalent } from "../lib/money.js";

const plugin: FastifyPluginAsync = async (app) => {
  app.get("/dashboard", { preHandler: app.authenticate }, async (request) => {
    const [subscriptions, recommendations, verified] = await Promise.all([
      app.db.subscription.findMany({ where: { userId: request.userId, status: { in: ["ACTIVE", "TRIAL", "NEEDS_REVIEW"] } }, orderBy: { nextRenewalAt: "asc" } }),
      app.db.recommendation.findMany({ where: { subscription: { userId: request.userId }, status: "PROPOSED" } }),
      app.db.savingsEvent.aggregate({ where: { subscription: { userId: request.userId }, status: "USER_VERIFIED" }, _sum: { verifiedAnnualSavingsCents: true } })
    ]);
    const monthlySpendCents = subscriptions.reduce((sum, item) => sum + monthlyEquivalent(item.amountCents, item.frequency.toLowerCase()), 0);
    return { monthlySpendCents, annualSpendCents: monthlySpendCents * 12, availableAnnualSavingsCents: recommendations.reduce((sum, item) => sum + item.estimatedAnnualSavingsCents, 0), lifetimeVerifiedSavingsCents: verified._sum.verifiedAnnualSavingsCents ?? 0, opportunityCount: recommendations.length, upcoming: subscriptions.slice(0, 5) };
  });
};
export default plugin;
