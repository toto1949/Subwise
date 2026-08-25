import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { AppError } from "../lib/errors.js";

const plugin: FastifyPluginAsync = async (app) => {
  app.addHook("preHandler", app.authenticate);
  app.get("/savings", async (request) => {
    const events = await app.db.savingsEvent.findMany({ where: { subscription: { userId: request.userId } }, orderBy: { createdAt: "desc" } });
    return { events, lifetimeVerifiedSavingsCents: events.filter((item) => item.status === "USER_VERIFIED").reduce((sum, item) => sum + (item.verifiedAnnualSavingsCents ?? 0), 0) };
  });
  app.post("/savings/:id/verify", async (request) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(request.params);
    const body = z.object({ outcome: z.enum(["cancelled", "changed_plan", "not_yet"]), verifiedAnnualSavingsCents: z.number().int().nonnegative().optional() }).parse(request.body);
    const event = await app.db.savingsEvent.findFirst({ where: { id, subscription: { userId: request.userId } } });
    if (!event) throw new AppError("SAVINGS_EVENT_NOT_FOUND", "Savings event not found", 404);
    if (body.outcome === "not_yet") return app.db.savingsEvent.update({ where: { id }, data: { status: "IN_PROGRESS" } });
    if (body.verifiedAnnualSavingsCents === undefined) throw new AppError("VERIFIED_AMOUNT_REQUIRED", "Verified savings amount is required", 400);
    return app.db.savingsEvent.update({ where: { id }, data: { action: body.outcome, status: "USER_VERIFIED", verifiedAnnualSavingsCents: body.verifiedAnnualSavingsCents, completedAt: new Date() } });
  });
};
export default plugin;
