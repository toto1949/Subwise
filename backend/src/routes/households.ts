import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { AppError } from "../lib/errors.js";
import { createHouseholdInviteToken, householdInviteURL, sendHouseholdInvitation, verifyHouseholdInviteToken, type HouseholdInviteDelivery } from "../services/household-invitations.js";

const householdInclude = {
  members: { select: { id: true, displayName: true, sharingMode: true, userId: true, invitedEmail: true } }
} as const;

const plugin: FastifyPluginAsync = async (app) => {
  app.get("/households/current", { preHandler: app.authenticate }, async (request) => {
    const household = await app.db.household.findFirst({
      where: { OR: [{ ownerId: request.userId }, { members: { some: { userId: request.userId } } }] },
      include: householdInclude
    });
    if (!household) throw new AppError("HOUSEHOLD_NOT_FOUND", "No household found", 404);
    return household;
  });

  app.post("/households", { preHandler: app.authenticate }, async (request, reply) => {
    const body = z.object({ name: z.string().trim().min(1).max(80) }).parse(request.body);
    const existing = await app.db.household.findFirst({ where: { ownerId: request.userId } });
    if (existing) throw new AppError("HOUSEHOLD_ALREADY_EXISTS", "You already own a household", 409);
    const user = await app.db.user.findUniqueOrThrow({ where: { id: request.userId } });
    return reply.status(201).send(await app.db.household.create({
      data: { ownerId: request.userId, name: body.name, members: { create: { userId: request.userId, displayName: user.displayName ?? "You", sharingMode: "OPTIMIZATION_ONLY" } } },
      include: householdInclude
    }));
  });

  app.post("/households/:id/invitations", { preHandler: app.authenticate }, async (request, reply) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(request.params);
    const body = z.object({
      email: z.string().trim().email(),
      displayName: z.string().trim().min(1).max(100),
      sharingMode: z.enum(["optimization_only", "service_name", "service_and_price"]).default("optimization_only")
    }).parse(request.body);
    const owned = await app.db.household.findFirst({ where: { id, ownerId: request.userId }, include: { owner: true } });
    if (!owned) throw new AppError("HOUSEHOLD_NOT_FOUND", "Household not found", 404);
    const email = body.email.toLowerCase();
    const existing = await app.db.householdMember.findFirst({ where: { householdId: id, invitedEmail: email, userId: null } });
    const member = existing
      ? await app.db.householdMember.update({ where: { id: existing.id }, data: { displayName: body.displayName, sharingMode: body.sharingMode.toUpperCase() as never } })
      : await app.db.householdMember.create({ data: { householdId: id, invitedEmail: email, displayName: body.displayName, sharingMode: body.sharingMode.toUpperCase() as never } });
    const token = createHouseholdInviteToken(member.id, app.config.ACCESS_TOKEN_SECRET);
    const inviteURL = householdInviteURL(app.config, token);
    let delivery: HouseholdInviteDelivery = "share_required";
    try {
      delivery = await sendHouseholdInvitation({
        config: app.config,
        memberId: member.id,
        recipientEmail: email,
        recipientName: member.displayName,
        inviterName: owned.owner.displayName ?? "A SubWise member",
        householdName: owned.name,
        inviteURL
      });
    } catch (error) {
      request.log.error({ err: error, operation: "household.invitation.email", memberId: member.id }, "Invitation email delivery failed; returning share fallback");
    }
    return reply.status(201).send({ member, inviteURL, delivery });
  });

  app.get("/household-invitations/:token", async (request) => {
    const { token } = z.object({ token: z.string().min(20).max(500) }).parse(request.params);
    const payload = verifyHouseholdInviteToken(token, app.config.ACCESS_TOKEN_SECRET);
    const member = await app.db.householdMember.findUnique({
      where: { id: payload.memberId },
      include: { household: { include: { owner: { select: { displayName: true } } } } }
    });
    if (!member) throw new AppError("HOUSEHOLD_INVITE_NOT_FOUND", "This household invitation no longer exists.", 404);
    if (member.userId) throw new AppError("HOUSEHOLD_INVITE_USED", "This household invitation has already been accepted.", 409);
    return {
      householdName: member.household.name,
      inviterName: member.household.owner.displayName ?? "A SubWise member",
      invitedName: member.displayName,
      expiresAt: new Date(payload.expiresAt * 1_000).toISOString()
    };
  });

  app.post("/household-invitations/:token/accept", { preHandler: app.authenticate }, async (request) => {
    const { token } = z.object({ token: z.string().min(20).max(500) }).parse(request.params);
    const payload = verifyHouseholdInviteToken(token, app.config.ACCESS_TOKEN_SECRET);
    const member = await app.db.householdMember.findUnique({ where: { id: payload.memberId }, include: { household: true } });
    if (!member) throw new AppError("HOUSEHOLD_INVITE_NOT_FOUND", "This household invitation no longer exists.", 404);
    if (member.userId && member.userId !== request.userId) throw new AppError("HOUSEHOLD_INVITE_USED", "This household invitation has already been accepted.", 409);
    if (member.household.ownerId === request.userId) throw new AppError("HOUSEHOLD_INVITE_OWNER", "You already own this household.", 409);
    const otherMembership = await app.db.householdMember.findFirst({ where: { userId: request.userId, householdId: { not: member.householdId } } });
    if (otherMembership) throw new AppError("HOUSEHOLD_MEMBERSHIP_EXISTS", "Leave your current household before joining another one.", 409);
    if (!member.userId) await app.db.householdMember.update({ where: { id: member.id }, data: { userId: request.userId } });
    return app.db.household.findUniqueOrThrow({ where: { id: member.householdId }, include: householdInclude });
  });

  app.delete("/households/:id/members/:memberId", { preHandler: app.authenticate }, async (request, reply) => {
    const { id, memberId } = z.object({ id: z.string().uuid(), memberId: z.string().uuid() }).parse(request.params);
    const owned = await app.db.household.findFirst({ where: { id, ownerId: request.userId } });
    if (!owned) throw new AppError("HOUSEHOLD_NOT_FOUND", "Household not found", 404);
    await app.db.householdMember.deleteMany({ where: { id: memberId, householdId: id, NOT: { userId: request.userId } } });
    return reply.status(204).send();
  });
};

export default plugin;
