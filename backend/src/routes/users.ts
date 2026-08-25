import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";

const plugin: FastifyPluginAsync = async (app) => {
  app.addHook("preHandler", app.authenticate);
  app.get("/me", async (request) => app.db.user.findUniqueOrThrow({ where: { id: request.userId }, select: { id: true, email: true, displayName: true, createdAt: true } }));
  app.patch("/me", async (request) => { const body = z.object({ displayName: z.string().min(1).max(100) }).parse(request.body); return app.db.user.update({ where: { id: request.userId }, data: body, select: { id: true, email: true, displayName: true } }); });
  app.get("/me/preferences", async (request) => app.db.notificationPreference.upsert({ where: { userId: request.userId }, create: { userId: request.userId }, update: {} }));
  app.patch("/me/preferences", async (request) => { const body = z.object({ reminderDays: z.array(z.number().int().min(0).max(30)).max(10), renewalAlerts: z.boolean(), priceAlerts: z.boolean() }).partial().parse(request.body); return app.db.notificationPreference.upsert({ where: { userId: request.userId }, create: { userId: request.userId, ...body }, update: body }); });
};
export default plugin;
