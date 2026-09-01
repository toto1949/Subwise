import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { AppError } from "../lib/errors.js";
import { candidateFromPlaidStream, detectRecurringTransactions, type DetectedCandidate } from "../domain/subscription-detection.js";
import { decryptToken, encryptToken } from "../lib/token-encryption.js";
import { PlaidClient } from "../services/plaid-client.js";
import { normalizeMerchant } from "../domain/merchant-resolver.js";
import { monthlyEquivalent } from "../lib/money.js";

const exchangeSchema = z.object({
  publicToken: z.string().min(1),
  institutionName: z.string().min(1).max(120).default("Connected account")
});
const frequency = z.enum(["weekly", "biweekly", "monthly", "quarterly", "semiannual", "yearly", "irregular"]);
const candidateSchema = z.object({
  id: z.string().min(1), rawMerchantName: z.string().min(1).max(200), displayName: z.string().min(1).max(100),
  amountCents: z.number().int().positive(), currency: z.literal("USD"), frequency,
  nextExpectedCharge: z.string().date().nullable(), category: z.string().min(1).max(60), confidence: z.number().min(0).max(1),
  needsReview: z.boolean(), paymentMethod: z.string().max(80).nullable(), evidenceCount: z.number().int().nonnegative(), source: z.literal("plaid"),
  usage: z.enum(["high", "medium", "low", "unknown"]).default("unknown"), isImportant: z.boolean().default(false)
});
const confirmSchema = z.object({ candidates: z.array(candidateSchema).min(1).max(100) });

const plugin: FastifyPluginAsync = async (app) => {
  const plaid = new PlaidClient(app.config);
  app.addHook("preHandler", app.authenticate);

  app.post("/discovery/plaid/link-token", async (request) => {
    const result = await plaid.createLinkToken(request.userId);
    return { linkToken: result.link_token, expiration: result.expiration };
  });

  app.post("/discovery/plaid/exchange", async (request, reply) => {
    const body = exchangeSchema.parse(request.body);
    const result = await plaid.exchangePublicToken(body.publicToken);
    const encryptedAccessToken = encryptToken(result.access_token, app.config.DATA_ENCRYPTION_KEY!);
    const connection = await app.db.institutionConnection.upsert({
      where: { providerItemId: result.item_id },
      create: { userId: request.userId, providerItemId: result.item_id, encryptedAccessToken, institutionName: body.institutionName },
      update: { userId: request.userId, encryptedAccessToken, institutionName: body.institutionName, status: "active" }
    });
    return reply.status(201).send({ connectionId: connection.id, institutionName: connection.institutionName });
  });

  app.get("/discovery/plaid/candidates", async (request) => {
    const connections = await app.db.institutionConnection.findMany({ where: { userId: request.userId, status: "active" } });
    if (!connections.length) throw new AppError("PLAID_CONNECTION_NOT_FOUND", "Connect a bank or card before scanning transactions.", 404);
    const all: DetectedCandidate[] = [];
    for (const connection of connections) {
      const accessToken = decryptToken(connection.encryptedAccessToken, app.config.DATA_ENCRYPTION_KEY!);
      try {
        const recurring = await plaid.recurring(accessToken);
        all.push(...recurring.outflow_streams.map(candidateFromPlaidStream).filter((item): item is DetectedCandidate => item !== null));
      } catch (error) {
        // Recurring Transactions is an optional Plaid add-on. The sync fallback uses cadence and amount evidence.
        if (!(error instanceof AppError) || !["PRODUCT_NOT_READY", "ADDITIONAL_CONSENT_REQUIRED", "PRODUCTS_NOT_SUPPORTED", "NO_RECURRING_TRANSACTIONS"].includes(error.code)) throw error;
        all.push(...detectRecurringTransactions(await plaid.sync(accessToken)));
      }
    }
    const existing = await app.db.subscription.findMany({ where: { userId: request.userId, status: { not: "CANCELLED" } }, select: { displayName: true, amountCents: true, frequency: true } });
    const deduplicated = all.filter((candidate, index) => all.findIndex((other) => other.displayName.toLowerCase() === candidate.displayName.toLowerCase() && other.amountCents === candidate.amountCents) === index);
    return {
      candidates: deduplicated.filter((candidate) => !existing.some((item) => normalizeMerchant(item.displayName).canonicalName === normalizeMerchant(candidate.displayName).canonicalName && item.amountCents === candidate.amountCents)),
      scannedConnections: connections.length
    };
  });

  app.post("/discovery/candidates/confirm", async (request, reply) => {
    const body = confirmSchema.parse(request.body);
    const created = await app.db.$transaction(async (tx) => {
      const values = [];
      for (const candidate of body.candidates) {
        const where = { userId_source_sourceExternalId: { userId: request.userId, source: "plaid", sourceExternalId: candidate.id } };
        const existing = await tx.subscription.findUnique({ where });
        const previousMonthly = existing ? monthlyEquivalent(existing.amountCents, existing.frequency.toLowerCase()) : null;
        const nextMonthly = monthlyEquivalent(candidate.amountCents, candidate.frequency);
        const subscription = await tx.subscription.upsert({
          where,
          create: {
            userId: request.userId, rawMerchantName: candidate.rawMerchantName, displayName: candidate.displayName,
            amountCents: candidate.amountCents, currency: candidate.currency, frequency: candidate.frequency.toUpperCase() as never,
            nextRenewalAt: candidate.nextExpectedCharge ? new Date(`${candidate.nextExpectedCharge}T12:00:00Z`) : null,
            status: candidate.needsReview ? "NEEDS_REVIEW" : "ACTIVE", category: candidate.category, usage: candidate.usage,
            isImportant: candidate.isImportant,
            valueScore: 50, source: "plaid", sourceExternalId: candidate.id, paymentMethodLabel: candidate.paymentMethod
          },
          update: {
            rawMerchantName: candidate.rawMerchantName, displayName: candidate.displayName, amountCents: candidate.amountCents,
            frequency: candidate.frequency.toUpperCase() as never,
            nextRenewalAt: candidate.nextExpectedCharge ? new Date(`${candidate.nextExpectedCharge}T12:00:00Z`) : null,
            status: candidate.needsReview ? "NEEDS_REVIEW" : "ACTIVE", category: candidate.category, usage: candidate.usage,
            isImportant: candidate.isImportant,
            paymentMethodLabel: candidate.paymentMethod
          }
        });
        if (previousMonthly !== null && previousMonthly !== nextMonthly) {
          await tx.priceObservation.create({ data: { subscriptionId: subscription.id, amountCents: previousMonthly, observedAt: existing!.updatedAt, source: "plaid", confirmedIncrease: previousMonthly < nextMonthly } });
          await tx.priceObservation.create({ data: { subscriptionId: subscription.id, amountCents: nextMonthly, observedAt: new Date(), source: "plaid", confirmedIncrease: false } });
        }
        values.push(subscription);
      }
      return values;
    });
    return reply.status(201).send({ subscriptions: created });
  });
};

export default plugin;
