import type { FastifyPluginAsync } from "fastify";
import { OpenAI } from "openai";
import { zodTextFormat } from "openai/helpers/zod";
import { z } from "zod";
import { monthlyEquivalent } from "../lib/money.js";
import { AppError } from "../lib/errors.js";

const AgentPlan = z.object({
  answer: z.string().min(1).max(4_000),
  recommendedSubscriptionIds: z.array(z.string().uuid()).max(5)
});
const clientSubscription = z.object({
  id: z.string().uuid(),
  merchant: z.string().min(1).max(100),
  monthlyEquivalentCents: z.number().int().nonnegative().max(10_000_000),
  usage: z.enum(["high", "medium", "low", "not_reported"]),
  valueScore: z.number().int().min(0).max(100),
  userPriority: z.enum(["keep", "normal"]),
  category: z.string().min(1).max(80),
  status: z.string().min(1).max(40)
});

type AgentContext = z.infer<typeof clientSubscription> & { allowedActions: string[] };

export function verifiedSavingsFor(ids: string[], context: AgentContext[]) {
  const unique = new Set(ids);
  return context
    .filter((item) => unique.has(item.id) && item.userPriority !== "keep")
    .reduce((sum, item) => sum + item.monthlyEquivalentCents, 0);
}

const plugin: FastifyPluginAsync = async (app) => {
  app.post("/agent/messages", { preHandler: app.authenticate }, async (request) => {
    const { message, conversationId, monthlySavingsGoalCents, subscriptions: suppliedSubscriptions } = z.object({ message: z.string().min(1).max(2_000), conversationId: z.string().uuid().optional(), monthlySavingsGoalCents: z.number().int().nonnegative().max(10_000_000), subscriptions: z.array(clientSubscription).max(100).default([]) }).parse(request.body);
    const subscriptions = await app.db.subscription.findMany({ where: { userId: request.userId, status: { in: ["ACTIVE", "TRIAL", "NEEDS_REVIEW"] } }, select: { id: true, displayName: true, amountCents: true, frequency: true, usage: true, valueScore: true, isImportant: true, category: true } });
    const databaseContext: AgentContext[] = subscriptions.map((item) => ({ id: item.id, merchant: item.displayName, monthlyEquivalentCents: monthlyEquivalent(item.amountCents, item.frequency.toLowerCase()), usage: item.usage === "unknown" ? "not_reported" : item.usage as "high" | "medium" | "low", valueScore: item.valueScore ?? 50, userPriority: item.isImportant ? "keep" : "normal", category: item.category, status: "saved", allowedActions: item.isImportant ? ["keep", "review"] : ["keep", "review", "cancel"] }));
    const context: AgentContext[] = (suppliedSubscriptions.length ? suppliedSubscriptions : databaseContext).map((item) => ({ ...item, allowedActions: item.userPriority === "keep" ? ["keep", "review"] : ["keep", "review", "cancel"] }));
    if (!app.config.OPENAI_API_KEY) throw new AppError("AI_NOT_CONFIGURED", "Add OPENAI_API_KEY to the server environment before using the Savings Agent", 503);

    const existingConversation = conversationId ? await app.db.aIConversation.findFirst({ where: { id: conversationId, userId: request.userId }, include: { messages: { orderBy: { createdAt: "desc" }, take: 20 } } }) : null;
    if (conversationId && !existingConversation) throw new AppError("CONVERSATION_NOT_FOUND", "Conversation not found", 404);
    const history = existingConversation?.messages.slice().reverse().map((item) => ({ role: item.role, content: item.content })) ?? [];
    const client = new OpenAI({ apiKey: app.config.OPENAI_API_KEY, timeout: 25_000, maxRetries: 1 });
    let response;
    try {
      response = await client.responses.parse({
        model: app.config.OPENAI_MODEL,
        instructions: "You are Subwise's advisory Savings Agent. Use only the supplied structured subscriptions and conversation history. Respect userPriority=keep and allowedActions. Recommend only subscription IDs present in the supplied data. Do not invent prices, discounts, eligibility, renewal dates, actions, or completed savings. Explain uncertainty, never guarantee savings, and never request credentials or sensitive financial data. Keep the response concise and actionable.",
        input: JSON.stringify({
          conversationHistory: history,
          userMessage: message,
          monthlySavingsGoalCents,
          currentMonthlySpendCents: context.reduce((sum, item) => sum + item.monthlyEquivalentCents, 0),
          subscriptions: context
        }),
        text: { format: zodTextFormat(AgentPlan, "savings_agent_plan") }
      });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      // Surface OpenAI failures as 502/504 instead of letting Vercel hang until client timeout (logs showed 18-30s)
      if (msg.toLowerCase().includes("timeout")) throw new AppError("AI_TIMEOUT", "Savings Agent timed out waiting for AI. Try again.", 504);
      throw new AppError("AI_UPSTREAM_ERROR", msg.slice(0, 300), 502);
    }
    if (!response.output_parsed) throw new AppError("AI_INVALID_RESPONSE", "The Savings Agent returned an invalid response", 502);

    const allowedIds = new Set(context.map((item) => item.id));
    const recommendedSubscriptionIds = [...new Set(response.output_parsed.recommendedSubscriptionIds)].filter((id) => allowedIds.has(id) && context.find((item) => item.id === id)?.userPriority !== "keep");
    const estimatedMonthlySavingsCents = verifiedSavingsFor(recommendedSubscriptionIds, context);
    const conversation = existingConversation ?? await app.db.aIConversation.create({ data: { userId: request.userId, title: message.slice(0, 80) } });
    await app.db.aIMessage.createMany({ data: [{ conversationId: conversation.id, role: "user", content: message, requestId: request.id }, { conversationId: conversation.id, role: "assistant", content: response.output_parsed.answer, requestId: request.id }] });
    return {
      conversationId: conversation.id,
      answer: response.output_parsed.answer,
      estimatedMonthlySavingsCents,
      recommendedSubscriptionIds,
      disclaimer: "Potential savings are calculated from your saved subscription prices. Verify plan terms and cancellation results before counting savings."
    };
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
