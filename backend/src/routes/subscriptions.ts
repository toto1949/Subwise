import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { AppError } from "../lib/errors.js";
import { annualize, monthlyEquivalent } from "../lib/money.js";
import { normalizeMerchant } from "../domain/merchant-resolver.js";
import { calculateValueScore } from "../domain/value-score.js";

const frequency = z.enum(["weekly", "biweekly", "monthly", "quarterly", "semiannual", "yearly", "irregular"]);
const createSchema = z.object({ displayName: z.string().min(1).max(100), planName: z.string().max(100).optional(), amountCents: z.number().int().nonnegative(), currency: z.literal("USD").default("USD"), frequency, nextRenewalAt: z.coerce.date().optional(), category: z.string().min(1), usage: z.enum(["high", "medium", "low", "unknown"]).default("unknown"), isTrial: z.boolean().default(false) });
const prismaFrequency = (value: z.infer<typeof frequency>) => value.toUpperCase() as "WEEKLY" | "BIWEEKLY" | "MONTHLY" | "QUARTERLY" | "SEMIANNUAL" | "YEARLY" | "IRREGULAR";

const plugin: FastifyPluginAsync = async (app) => {
  app.addHook("preHandler", app.authenticate);
  app.get("/subscriptions", async (request) => {
    const query = z.object({ status: z.string().optional(), category: z.string().optional() }).parse(request.query);
    return app.db.subscription.findMany({ where: { userId: request.userId, ...(query.status ? { status: query.status.toUpperCase() as never } : {}), ...(query.category ? { category: query.category } : {}) }, orderBy: { nextRenewalAt: "asc" } });
  });
  app.post("/subscriptions", async (request, reply) => {
    const body = createSchema.parse(request.body);
    const merchant = normalizeMerchant(body.displayName);
    const score = calculateValueScore({ monthlyCents: monthlyEquivalent(body.amountCents, body.frequency), usage: body.usage, householdUsers: 1, isDuplicate: false, hasCheaperAlternative: false, isImportant: false, priceIncreasePercent: 0, isTrial: body.isTrial });
    const subscription = await app.db.subscription.create({ data: { userId: request.userId, rawMerchantName: body.displayName, displayName: merchant.canonicalName, planName: body.planName, amountCents: body.amountCents, currency: body.currency, frequency: prismaFrequency(body.frequency), nextRenewalAt: body.nextRenewalAt, category: body.category, usage: body.usage, status: body.isTrial ? "TRIAL" : "ACTIVE", valueScore: score.score } });
    return reply.status(201).send({ ...subscription, monthlyEquivalentCents: monthlyEquivalent(body.amountCents, body.frequency), annualCostCents: annualize(body.amountCents, body.frequency), scoreReasons: score.reasonCodes });
  });
  app.get("/subscriptions/:id", async (request) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(request.params);
    const item = await app.db.subscription.findFirst({ where: { id, userId: request.userId }, include: { priceObservations: { orderBy: { observedAt: "asc" } }, trial: true, merchant: { include: { plans: true, benefits: true, cancellationGuide: { include: { steps: { orderBy: { sequence: "asc" } } } } } } } });
    if (!item) throw new AppError("SUBSCRIPTION_NOT_FOUND", "Subscription not found", 404);
    return item;
  });
  app.patch("/subscriptions/:id", async (request) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(request.params);
    const body = createSchema.partial().parse(request.body);
    const found = await app.db.subscription.findFirst({ where: { id, userId: request.userId }, select: { id: true } });
    if (!found) throw new AppError("SUBSCRIPTION_NOT_FOUND", "Subscription not found", 404);
    const { frequency: nextFrequency, isTrial, ...fields } = body;
    return app.db.subscription.update({ where: { id }, data: { ...fields, ...(nextFrequency ? { frequency: prismaFrequency(nextFrequency) } : {}), ...(isTrial !== undefined ? { status: isTrial ? "TRIAL" : "ACTIVE" } : {}) } });
  });
  app.delete("/subscriptions/:id", async (request, reply) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(request.params);
    const result = await app.db.subscription.deleteMany({ where: { id, userId: request.userId } });
    if (!result.count) throw new AppError("SUBSCRIPTION_NOT_FOUND", "Subscription not found", 404);
    return reply.status(204).send();
  });
};
export default plugin;
