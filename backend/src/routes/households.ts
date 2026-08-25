import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { AppError } from "../lib/errors.js";

const plugin: FastifyPluginAsync = async (app) => {
  app.addHook("preHandler", app.authenticate);
  app.get("/households/current", async (request) => {
    const household = await app.db.household.findFirst({ where: { OR: [{ ownerId: request.userId }, { members: { some: { userId: request.userId } } }] }, include: { members: { select: { id: true, displayName: true, sharingMode: true, userId: true } } } });
    if (!household) throw new AppError("HOUSEHOLD_NOT_FOUND", "No household found", 404);
    return household;
  });
  app.post("/households", async (request, reply) => {
    const body = z.object({ name: z.string().min(1).max(80) }).parse(request.body);
    const existing = await app.db.household.findFirst({ where: { ownerId: request.userId } });
    if (existing) throw new AppError("HOUSEHOLD_ALREADY_EXISTS", "You already own a household", 409);
    const user = await app.db.user.findUniqueOrThrow({ where: { id: request.userId } });
    return reply.status(201).send(await app.db.household.create({ data: { ownerId: request.userId, name: body.name, members: { create: { userId: request.userId, displayName: user.displayName ?? "You", sharingMode: "OPTIMIZATION_ONLY" } } }, include: { members: true } }));
  });
  app.post("/households/:id/invitations", async (request, reply) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(request.params);
    const body = z.object({ email: z.string().email(), displayName: z.string().min(1), sharingMode: z.enum(["optimization_only", "service_name", "service_and_price"]).default("optimization_only") }).parse(request.body);
    const owned = await app.db.household.findFirst({ where: { id, ownerId: request.userId } });
    if (!owned) throw new AppError("HOUSEHOLD_NOT_FOUND", "Household not found", 404);
    const member = await app.db.householdMember.create({ data: { householdId: id, invitedEmail: body.email.toLowerCase(), displayName: body.displayName, sharingMode: body.sharingMode.toUpperCase() as never } });
    return reply.status(201).send(member);
  });
  app.delete("/households/:id/members/:memberId", async (request, reply) => {
    const { id, memberId } = z.object({ id: z.string().uuid(), memberId: z.string().uuid() }).parse(request.params);
    const owned = await app.db.household.findFirst({ where: { id, ownerId: request.userId } });
    if (!owned) throw new AppError("HOUSEHOLD_NOT_FOUND", "Household not found", 404);
    await app.db.householdMember.deleteMany({ where: { id: memberId, householdId: id, NOT: { userId: request.userId } } });
    return reply.status(204).send();
  });
};
export default plugin;
