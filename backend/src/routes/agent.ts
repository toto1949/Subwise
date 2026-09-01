import type { FastifyPluginAsync } from "fastify";
import { OpenAI } from "openai";
import { zodTextFormat } from "openai/helpers/zod";
import { z } from "zod";
import { monthlyEquivalent } from "../lib/money.js";
import { AppError } from "../lib/errors.js";
import { optimizeSubscriptions } from "../domain/optimization-engine.js";
import { normalizeMerchant } from "../domain/merchant-resolver.js";

const AgentSection = z.object({
  title: z.string().min(1).max(80),
  body: z.string().min(1).max(600),
  bullets: z.array(z.string().min(1).max(240)).max(4).default([])
});
const AgentPlan = z.object({
  headline: z.string().min(1).max(100),
  summary: z.string().min(1).max(1_000),
  sections: z.array(AgentSection).min(1).max(4),
  recommendedActionIds: z.array(z.string().min(1).max(40)).max(5)
});
const clientSubscription = z.object({
  id: z.string().uuid(),
  merchant: z.string().min(1).max(100),
  monthlyEquivalentCents: z.number().int().nonnegative().max(10_000_000),
  usage: z.enum(["high", "medium", "low", "not_reported"]),
  valueScore: z.number().int().min(0).max(100),
  userPriority: z.enum(["keep", "normal"]),
  category: z.string().min(1).max(80),
  status: z.string().min(1).max(40),
  billingFrequency: z.enum(["weekly", "monthly", "yearly"]).default("monthly"),
  previousMonthlyCents: z.number().int().nonnegative().max(10_000_000).nullable().optional()
});

type AgentContext = z.infer<typeof clientSubscription> & {
  allowedActions: string[];
  normalizedMerchant?: string;
  sameMerchantCount?: number;
  sameCategoryCount?: number;
};

function enrichRelationships(items: AgentContext[]): AgentContext[] {
  const merchantCounts = Map.groupBy(items, (item) => normalizeAgentMerchant(item.merchant));
  const categoryCounts = Map.groupBy(items, (item) => item.category.toLowerCase());
  return items.map((item) => {
    const normalizedMerchant = normalizeAgentMerchant(item.merchant);
    return {
      ...item,
      normalizedMerchant,
      sameMerchantCount: merchantCounts.get(normalizedMerchant)?.length ?? 1,
      sameCategoryCount: categoryCounts.get(item.category.toLowerCase())?.length ?? 1
    };
  });
}

function normalizeAgentMerchant(value: string) {
  const planWords = new Set(["premium", "standard", "basic", "plus", "pro", "monthly", "annual", "yearly", "subscription", "plan"]);
  return value.toLowerCase().split(/[^a-z0-9]+/).filter((part) => part && !planWords.has(part)).join(" ");
}

export function verifiedSavingsFor(ids: string[], context: Array<Pick<AgentContext, "id" | "userPriority" | "monthlyEquivalentCents">>) {
  const unique = new Set(ids);
  return context
    .filter((item) => unique.has(item.id) && item.userPriority !== "keep")
    .reduce((sum, item) => sum + item.monthlyEquivalentCents, 0);
}

const plugin: FastifyPluginAsync = async (app) => {
  app.post("/agent/messages", { preHandler: app.authenticate }, async (request) => {
    const { message, conversationId, monthlySavingsGoalCents, subscriptions: suppliedSubscriptions } = z.object({ message: z.string().min(1).max(2_000), conversationId: z.string().uuid().optional(), monthlySavingsGoalCents: z.number().int().nonnegative().max(10_000_000), subscriptions: z.array(clientSubscription).max(100).default([]) }).parse(request.body);
    const subscriptions = await app.db.subscription.findMany({ where: { userId: request.userId, status: { in: ["ACTIVE", "TRIAL", "NEEDS_REVIEW"] } }, select: { id: true, displayName: true, amountCents: true, frequency: true, usage: true, valueScore: true, isImportant: true, category: true } });
    const databaseContext: AgentContext[] = subscriptions.map((item) => ({ id: item.id, merchant: item.displayName, monthlyEquivalentCents: monthlyEquivalent(item.amountCents, item.frequency.toLowerCase()), usage: item.usage === "unknown" ? "not_reported" : item.usage as "high" | "medium" | "low", valueScore: item.valueScore ?? 50, userPriority: item.isImportant ? "keep" : "normal", category: item.category, status: "saved", billingFrequency: item.frequency.toLowerCase() === "yearly" ? "yearly" : item.frequency.toLowerCase() === "weekly" ? "weekly" : "monthly", allowedActions: item.isImportant ? ["keep", "review"] : ["keep", "review", "cancel"] }));
    const context = enrichRelationships((suppliedSubscriptions.length ? suppliedSubscriptions : databaseContext).map((item) => ({ ...item, allowedActions: item.userPriority === "keep" ? ["keep", "review"] : ["keep", "review", "cancel"] })));
    if (!app.config.OPENAI_API_KEY) throw new AppError("AI_NOT_CONFIGURED", "Add OPENAI_API_KEY to the server environment before using the Savings Agent", 503);

    const existingConversation = conversationId ? await app.db.aIConversation.findFirst({ where: { id: conversationId, userId: request.userId }, include: { messages: { orderBy: { createdAt: "desc" }, take: 20 } } }) : null;
    if (conversationId && !existingConversation) throw new AppError("CONVERSATION_NOT_FOUND", "Conversation not found", 404);
    const history = existingConversation?.messages.slice().reverse().map((item) => ({ role: item.role, content: item.content })) ?? [];
    const merchants = await app.db.merchant.findMany({
      where: { active: true },
      include: { plans: true, outgoingAlternatives: { include: { alternative: { include: { plans: true } } } } }
    });
    const merchantByName = new Map(merchants.map((merchant) => [normalizeMerchant(merchant.canonicalName).canonicalName.toLowerCase(), merchant]));
    const opportunities = optimizeSubscriptions(context.map((item) => {
      const merchant = merchantByName.get(normalizeMerchant(item.merchant).canonicalName.toLowerCase());
      return {
        id: item.id, merchant: item.merchant, category: item.category, monthlyCents: item.monthlyEquivalentCents,
        valueScore: item.valueScore, usage: item.usage === "not_reported" ? "unknown" as const : item.usage,
        isImportant: item.userPriority === "keep", currentFrequency: item.billingFrequency,
        previousMonthlyCents: item.previousMonthlyCents ?? undefined,
        plans: merchant?.plans.filter((plan) => plan.sourceUrl && plan.verifiedAt).map((plan) => ({
          name: plan.name, monthlyCents: monthlyEquivalent(plan.priceCents, plan.frequency.toLowerCase()), frequency: plan.frequency.toLowerCase(),
          planType: plan.planType, householdSize: plan.householdSize, eligibilityType: plan.eligibilityType,
          sourceUrl: plan.sourceUrl!, verifiedAt: plan.verifiedAt!
        })) ?? [],
        alternatives: merchant?.outgoingAlternatives.flatMap((relation) => relation.alternative.plans
          .filter((plan) => plan.sourceUrl && plan.verifiedAt)
          .map((plan) => ({ merchant: relation.alternative.canonicalName, rationale: relation.rationale, plan: {
            name: plan.name, monthlyCents: monthlyEquivalent(plan.priceCents, plan.frequency.toLowerCase()), frequency: plan.frequency.toLowerCase(),
            planType: plan.planType, householdSize: plan.householdSize, eligibilityType: plan.eligibilityType,
            sourceUrl: plan.sourceUrl!, verifiedAt: plan.verifiedAt!
          } }))) ?? []
      };
    })).map((opportunity, index) => ({ id: `action_${index + 1}`, ...opportunity }));
    const client = new OpenAI({ apiKey: app.config.OPENAI_API_KEY, timeout: 25_000, maxRetries: 1 });
    let response;
    try {
      response = await client.responses.parse({
        model: app.config.OPENAI_MODEL,
        instructions: "You are SubWise's advisory Savings Agent. Return a short headline, summary, and 1-4 clearly labeled sections with optional bullets. Use only the supplied facts, availableActions, and conversation history. Build toward the stated monthly goal, but say when verified opportunities cannot meet it. Respect userPriority=keep and allowedActions. Select only IDs from availableActions; never invent an action, price, alternative, eligibility, renewal date, usage claim, or completed savings. An exact merchant duplicate is only a comparison signal; category overlap is never proof of duplication. A cheaper alternative must be framed as a comparison because features differ. Never request credentials or sensitive financial data.",
        input: JSON.stringify({
          conversationHistory: history,
          userMessage: message,
          monthlySavingsGoalCents,
          currentMonthlySpendCents: context.reduce((sum, item) => sum + item.monthlyEquivalentCents, 0),
          subscriptions: context,
          availableActions: opportunities
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

    const allowedActionIds = new Set(opportunities.map((item) => item.id));
    const selectedActions = [...new Set(response.output_parsed.recommendedActionIds)]
      .filter((id) => allowedActionIds.has(id))
      .map((id) => opportunities.find((item) => item.id === id)!)
      .filter((item) => context.find((value) => value.id === item.subscriptionIds[0])?.userPriority !== "keep");
    const bestSavingsBySubscription = new Map<string, number>();
    for (const action of selectedActions) {
      const id = action.subscriptionIds[0];
      if (id) bestSavingsBySubscription.set(id, Math.max(bestSavingsBySubscription.get(id) ?? 0, action.estimatedMonthlySavingsCents));
    }
    const recommendedSubscriptionIds = [...bestSavingsBySubscription.keys()];
    const estimatedMonthlySavingsCents = [...bestSavingsBySubscription.values()].reduce((sum, value) => sum + value, 0);
    const conversation = existingConversation ?? await app.db.aIConversation.create({ data: { userId: request.userId, title: message.slice(0, 80) } });
    await app.db.aIMessage.createMany({ data: [{ conversationId: conversation.id, role: "user", content: message, requestId: request.id }, { conversationId: conversation.id, role: "assistant", content: `${response.output_parsed.headline}\n\n${response.output_parsed.summary}`, requestId: request.id }] });
    return {
      conversationId: conversation.id,
      answer: response.output_parsed.summary,
      headline: response.output_parsed.headline,
      sections: response.output_parsed.sections,
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
