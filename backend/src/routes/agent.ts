import type { FastifyPluginAsync } from "fastify";
import { OpenAI } from "openai";
import { zodTextFormat } from "openai/helpers/zod";
import { z } from "zod";
import { monthlyEquivalent } from "../lib/money.js";
import { AppError } from "../lib/errors.js";

const AgentResponse = z.object({ answer: z.string(), estimatedMonthlySavingsCents: z.number().int().nonnegative().nullable(), recommendedSubscriptionIds: z.array(z.string()), disclaimer: z.string() });
const plugin: FastifyPluginAsync = async (app) => {
  app.post("/agent/messages", { preHandler: app.authenticate }, async (request) => {
    const { message, conversationId } = z.object({ message: z.string().min(1).max(2_000), conversationId: z.string().uuid().optional() }).parse(request.body);
    const subscriptions = await app.db.subscription.findMany({ where: { userId: request.userId, status: { in: ["ACTIVE", "TRIAL", "NEEDS_REVIEW"] } }, select: { id: true, displayName: true, amountCents: true, frequency: true, usage: true, valueScore: true, isImportant: true, category: true } });
    const context = subscriptions.map((item) => ({ id: item.id, merchant: item.displayName, monthlyEquivalentCents: monthlyEquivalent(item.amountCents, item.frequency.toLowerCase()), usage: item.usage, valueScore: item.valueScore, userPriority: item.isImportant ? "keep" : "normal", category: item.category, allowedActions: ["keep", "review", "cancel"] }));
    let parsed: z.infer<typeof AgentResponse>;
    if (app.config.OPENAI_API_KEY) {
      const client = new OpenAI({ apiKey: app.config.OPENAI_API_KEY });
      const response = await client.responses.parse({ model: app.config.OPENAI_MODEL, instructions: "You are Subwise's advisory Savings Agent. Use only the supplied structured subscription context. Never claim an action was completed, never guarantee eligibility or savings, and call savings estimated. Do not request bank credentials or sensitive account data.", input: JSON.stringify({ userMessage: message, currentMonthlySpendCents: context.reduce((sum, item) => sum + item.monthlyEquivalentCents, 0), subscriptions: context }), text: { format: zodTextFormat(AgentResponse, "savings_agent_response") } });
      if (!response.output_parsed) throw new AppError("AI_INVALID_RESPONSE", "The Savings Agent returned an invalid response", 502);
      parsed = response.output_parsed;
    } else if (app.config.NODE_ENV !== "production") {
      const candidates = context.filter((item) => !item.userPriority.includes("keep") && (item.valueScore ?? 50) < 50).sort((a, b) => b.monthlyEquivalentCents - a.monthlyEquivalentCents).slice(0, 3);
      const savings = candidates.reduce((sum, item) => sum + item.monthlyEquivalentCents, 0);
      parsed = {
        answer: candidates.length ? `Start by reviewing ${candidates.map((item) => item.merchant).join(", ")}. They represent up to $${(savings / 100).toFixed(2)} per month. Keep anything essential and use the guided flow before changing a plan.` : "Your saved subscriptions look healthy. Add usage details or flag a service for review to get a more targeted plan.",
        estimatedMonthlySavingsCents: savings,
        recommendedSubscriptionIds: candidates.map((item) => item.id),
        disclaimer: "Internal development analysis using structured subscription data. Savings are estimates."
      };
    } else {
      throw new AppError("AI_NOT_CONFIGURED", "The Savings Agent is not configured", 503);
    }
    const conversation = conversationId ? await app.db.aIConversation.findFirst({ where: { id: conversationId, userId: request.userId } }) : await app.db.aIConversation.create({ data: { userId: request.userId, title: message.slice(0, 80) } });
    if (!conversation) throw new AppError("CONVERSATION_NOT_FOUND", "Conversation not found", 404);
    await app.db.aIMessage.createMany({ data: [{ conversationId: conversation.id, role: "user", content: message, requestId: request.id }, { conversationId: conversation.id, role: "assistant", content: parsed.answer, requestId: request.id }] });
    return { conversationId: conversation.id, ...parsed };
  });
  app.get("/agent/conversations", { preHandler: app.authenticate }, async (request) => app.db.aIConversation.findMany({ where: { userId: request.userId }, orderBy: { updatedAt: "desc" }, select: { id: true, title: true, createdAt: true, updatedAt: true } }));
  app.get("/agent/conversations/:id", { preHandler: app.authenticate }, async (request) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(request.params);
    const conversation = await app.db.aIConversation.findFirst({ where: { id, userId: request.userId }, include: { messages: { orderBy: { createdAt: "asc" } } } });
    if (!conversation) throw new AppError("CONVERSATION_NOT_FOUND", "Conversation not found", 404);
    return conversation;
  });
};
export default plugin;
