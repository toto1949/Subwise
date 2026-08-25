import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { AppError } from "../lib/errors.js";

const schema = z.object({ displayName: z.string().min(1), endsAt: z.coerce.date(), renewalPriceCents: z.number().int().nonnegative(), frequency: z.enum(["weekly", "monthly", "yearly"]), category: z.string().default("Other"), source: z.enum(["manual", "ocr", "share_extension"]).default("manual"), extractionConfidence: z.number().min(0).max(1).optional() });
const plugin: FastifyPluginAsync = async (app) => {
  app.addHook("preHandler", app.authenticate);
  app.get("/trials", async (request) => app.db.trial.findMany({ where: { subscription: { userId: request.userId } }, include: { subscription: true }, orderBy: { endsAt: "asc" } }));
  app.post("/trials", async (request, reply) => {
    const body = schema.parse(request.body);
    const subscription = await app.db.subscription.create({ data: { userId: request.userId, rawMerchantName: body.displayName, displayName: body.displayName, amountCents: body.renewalPriceCents, currency: "USD", frequency: body.frequency.toUpperCase() as never, nextRenewalAt: body.endsAt, status: "TRIAL", category: body.category, trial: { create: { endsAt: body.endsAt, renewalPriceCents: body.renewalPriceCents, frequency: body.frequency.toUpperCase() as never, source: body.source, extractionConfidence: body.extractionConfidence } } }, include: { trial: true } });
    return reply.status(201).send(subscription);
  });
  app.delete("/trials/:id", async (request, reply) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(request.params);
    const trial = await app.db.trial.findFirst({ where: { id, subscription: { userId: request.userId } } });
    if (!trial) throw new AppError("TRIAL_NOT_FOUND", "Trial not found", 404);
    await app.db.subscription.delete({ where: { id: trial.subscriptionId } });
    return reply.status(204).send();
  });
  app.post("/imports/ocr-result", async (request) => {
    const candidate = schema.extend({ normalizedTextHash: z.string().min(32), userConfirmed: z.literal(true) }).parse(request.body);
    return { candidate, accepted: true, message: "OCR result validated. Submit it to /trials to create a trial." };
  });
};
export default plugin;
