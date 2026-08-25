import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { AppError } from "../lib/errors.js";

const plugin: FastifyPluginAsync = async (app) => {
  app.addHook("preHandler", app.authenticate);
  app.get("/subscriptions/:id/cancellation", async (request) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(request.params);
    const subscription = await app.db.subscription.findFirst({ where: { id, userId: request.userId }, include: { merchant: { include: { cancellationGuide: { include: { steps: { orderBy: { sequence: "asc" } } } } } } } });
    if (!subscription) throw new AppError("SUBSCRIPTION_NOT_FOUND", "Subscription not found", 404);
    if (!subscription.merchant?.cancellationGuide) throw new AppError("CANCELLATION_GUIDE_UNAVAILABLE", "No verified cancellation guide is available", 404);
    return subscription.merchant.cancellationGuide;
  });
  app.post("/subscriptions/:id/cancellation/status", async (request, reply) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(request.params);
    const body = z.object({ outcome: z.enum(["started", "cancelled", "changed_plan", "not_yet"]), verifiedAnnualSavingsCents: z.number().int().nonnegative().optional() }).parse(request.body);
    const subscription = await app.db.subscription.findFirst({ where: { id, userId: request.userId } });
    if (!subscription) throw new AppError("SUBSCRIPTION_NOT_FOUND", "Subscription not found", 404);
    const status = body.outcome === "cancelled" || body.outcome === "changed_plan" ? "USER_VERIFIED" : body.outcome === "started" ? "IN_PROGRESS" : "PROPOSED";
    const event = await app.db.savingsEvent.create({ data: { subscriptionId: id, action: body.outcome, estimatedAnnualSavingsCents: subscription.amountCents * (subscription.frequency === "YEARLY" ? 1 : 12), verifiedAnnualSavingsCents: body.verifiedAnnualSavingsCents, status, completedAt: status === "USER_VERIFIED" ? new Date() : null } });
    if (body.outcome === "cancelled") await app.db.subscription.update({ where: { id }, data: { status: "CANCELLED" } });
    return reply.status(201).send(event);
  });
};
export default plugin;
