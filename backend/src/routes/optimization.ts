import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { monthlyEquivalent } from "../lib/money.js";
import { optimizeSubscriptions } from "../domain/optimization-engine.js";
import { AppError } from "../lib/errors.js";
import { normalizeMerchant } from "../domain/merchant-resolver.js";

const plugin: FastifyPluginAsync = async (app) => {
  app.addHook("preHandler", app.authenticate);
  app.post("/optimization/generate", async (request, reply) => {
    const subscriptions = await app.db.subscription.findMany({ where: { userId: request.userId, status: { in: ["ACTIVE", "TRIAL", "NEEDS_REVIEW"] } }, include: { priceObservations: { where: { confirmedIncrease: true }, orderBy: { observedAt: "asc" } } } });
    const merchants = await app.db.merchant.findMany({ where: { active: true }, include: { plans: true } });
    const householdMemberships = await app.db.householdMember.count({ where: { household: { ownerId: request.userId } } });
    const merchantByName = new Map(merchants.map((merchant) => [normalizeMerchant(merchant.canonicalName).canonicalName.toLowerCase(), merchant]));
    const results = optimizeSubscriptions(subscriptions.map((item) => {
      const monthlyCents = monthlyEquivalent(item.amountCents, item.frequency.toLowerCase());
      const merchant = merchantByName.get(normalizeMerchant(item.displayName).canonicalName.toLowerCase());
      const previous = item.priceObservations.find((observation) => observation.amountCents < monthlyCents);
      return {
        id: item.id, merchant: item.displayName, category: item.category, monthlyCents, currentPlanName: item.planName,
        currentFrequency: item.frequency.toLowerCase(), valueScore: item.valueScore ?? 50,
        usage: item.usage as "high" | "medium" | "low" | "unknown", isImportant: item.isImportant,
        previousMonthlyCents: previous?.amountCents, householdSize: Math.max(1, householdMemberships + 1),
        plans: merchant?.plans.filter((plan) => plan.sourceUrl && plan.verifiedAt).map((plan) => ({
          name: plan.name, monthlyCents: monthlyEquivalent(plan.priceCents, plan.frequency.toLowerCase()), frequency: plan.frequency.toLowerCase(),
          planType: plan.planType, householdSize: plan.householdSize, eligibilityType: plan.eligibilityType,
          sourceUrl: plan.sourceUrl!, verifiedAt: plan.verifiedAt!
        })) ?? []
      };
    }));
    const plan = await app.db.$transaction(async (tx) => {
      await tx.recommendation.updateMany({ where: { subscription: { userId: request.userId }, status: "PROPOSED" }, data: { status: "DISMISSED" } });
      const recommendations = await Promise.all(results.map((result) => tx.recommendation.create({ data: { subscriptionId: result.subscriptionIds[0], type: result.type, estimatedMonthlySavingsCents: result.estimatedMonthlySavingsCents, estimatedAnnualSavingsCents: result.estimatedAnnualSavingsCents, confidence: result.confidence, effortMinutes: result.effortMinutes, reasonCodes: result.reasonCodes, explanation: result.explanation } })));
      const currentMonthlyCents = subscriptions.reduce((sum, item) => sum + monthlyEquivalent(item.amountCents, item.frequency.toLowerCase()), 0);
      const bestSavingsBySubscription = new Map<string, number>();
      for (const [index, result] of results.entries()) {
        const key = result.subscriptionIds[0] ?? `unknown:${index}`;
        bestSavingsBySubscription.set(key, Math.max(bestSavingsBySubscription.get(key) ?? 0, result.estimatedMonthlySavingsCents));
      }
      const projectedSavings = [...bestSavingsBySubscription.values()].reduce((sum, value) => sum + value, 0);
      return tx.optimizationPlan.create({ data: { userId: request.userId, currentMonthlyCents, projectedMonthlyCents: Math.max(0, currentMonthlyCents - projectedSavings), actions: { create: recommendations.map((item, index) => ({ recommendationId: item.id, sequence: index + 1 })) } }, include: { actions: { include: { recommendation: true }, orderBy: { sequence: "asc" } } } });
    });
    return reply.status(201).send(plan);
  });
  app.get("/optimization/:id", async (request) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(request.params);
    const plan = await app.db.optimizationPlan.findFirst({ where: { id, userId: request.userId }, include: { actions: { include: { recommendation: true }, orderBy: { sequence: "asc" } } } });
    if (!plan) throw new AppError("OPTIMIZATION_NOT_FOUND", "Optimization plan not found", 404);
    return plan;
  });
  app.post("/optimization/:id/apply", async (request) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(request.params);
    const { recommendationIds } = z.object({ recommendationIds: z.array(z.string().uuid()).min(1) }).parse(request.body);
    const plan = await app.db.optimizationPlan.findFirst({ where: { id, userId: request.userId }, include: { actions: true } });
    if (!plan) throw new AppError("OPTIMIZATION_NOT_FOUND", "Optimization plan not found", 404);
    const allowed = new Set(plan.actions.map((item) => item.recommendationId));
    if (recommendationIds.some((item) => !allowed.has(item))) throw new AppError("INVALID_PLAN_ACTION", "One or more actions are not part of this plan", 400);
    await app.db.$transaction([app.db.optimizationPlan.update({ where: { id }, data: { status: "ACCEPTED" } }), app.db.optimizationAction.updateMany({ where: { planId: id, recommendationId: { in: recommendationIds } }, data: { status: "ACCEPTED" } }), app.db.recommendation.updateMany({ where: { id: { in: recommendationIds } }, data: { status: "ACCEPTED" } })]);
    return { status: "accepted", nextActionId: plan.actions.find((item) => recommendationIds.includes(item.recommendationId))?.id ?? null };
  });
  app.get("/recommendations", async (request) => app.db.recommendation.findMany({ where: { subscription: { userId: request.userId }, status: { in: ["PROPOSED", "ACCEPTED", "IN_PROGRESS"] } }, orderBy: [{ estimatedAnnualSavingsCents: "desc" }, { confidence: "desc" }] }));
  app.post("/recommendations/:id/accept", async (request) => updateRecommendation(app, request.userId, request.params, "ACCEPTED"));
  app.post("/recommendations/:id/dismiss", async (request) => updateRecommendation(app, request.userId, request.params, "DISMISSED"));
};

async function updateRecommendation(app: Parameters<FastifyPluginAsync>[0], userId: string, params: unknown, status: "ACCEPTED" | "DISMISSED") {
  const { id } = z.object({ id: z.string().uuid() }).parse(params);
  const item = await app.db.recommendation.findFirst({ where: { id, subscription: { userId } } });
  if (!item) throw new AppError("RECOMMENDATION_NOT_FOUND", "Recommendation not found", 404);
  return app.db.recommendation.update({ where: { id }, data: { status } });
}
export default plugin;
