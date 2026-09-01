import Fastify from "fastify";
import cors from "@fastify/cors";
import helmet from "@fastify/helmet";
import rateLimit from "@fastify/rate-limit";
import swagger from "@fastify/swagger";
import swaggerUI from "@fastify/swagger-ui";
import type { Config } from "./config.js";
import { errorHandler } from "./lib/errors.js";
import database from "./plugins/database.js";
import auth from "./plugins/auth.js";
import authRoutes from "./routes/auth.js";
import userRoutes from "./routes/users.js";
import dashboardRoutes from "./routes/dashboard.js";
import subscriptionRoutes from "./routes/subscriptions.js";
import optimizationRoutes from "./routes/optimization.js";
import savingsRoutes from "./routes/savings.js";
import householdRoutes from "./routes/households.js";
import agentRoutes from "./routes/agent.js";
import trialRoutes from "./routes/trials.js";
import cancellationRoutes from "./routes/cancellation.js";
import discoveryRoutes from "./routes/discovery.js";
import legalRoutes from "./routes/legal.js";
import { escapeHTML, verifyHouseholdInviteToken } from "./services/household-invitations.js";

declare module "fastify" { interface FastifyInstance { config: Config } }

export function buildApp(config: Config) {
  const app = Fastify({ logger: { level: config.LOG_LEVEL, redact: ["req.headers.authorization", "req.headers.plaid-client-id", "req.headers.plaid-secret", "req.body.identityToken", "req.body.authorizationCode", "req.body.refreshToken", "req.body.accessToken", "req.body.publicToken"] }, requestIdHeader: "x-request-id", trustProxy: true });
  app.decorate("config", config);
  app.setErrorHandler(errorHandler);
  app.register(helmet, { contentSecurityPolicy: false });
  app.register(cors, { origin: false });
  app.register(rateLimit, { max: 120, timeWindow: "1 minute", keyGenerator: (request) => request.userId || request.ip });
  app.register(swagger, { openapi: { info: { title: "Subwise API", version: "1.0.0" }, servers: [{ url: "/api/v1" }] } });
  app.register(swaggerUI, { routePrefix: "/docs" });
  app.register(database);
  app.register(auth);
  app.get("/health", async () => ({ status: "ok" }));
  app.get("/.well-known/apple-app-site-association", async (_request, reply) => reply.type("application/json").send({
    applinks: { details: [{ appIDs: ["3K82B6HTAT.com.toto.Subwise"], components: [
      { "/": "/plaid/*", comment: "Plaid OAuth return links" },
      { "/": "/household/invite/*", comment: "SubWise household invitation links" }
    ] }] }
  }));
  app.get("/plaid/oauth", async (_request, reply) => reply.type("text/html").send("<!doctype html><meta name='viewport' content='width=device-width'><title>Return to SubWise</title><main style='font:16px -apple-system;padding:40px;max-width:520px;margin:auto'><h1>Return to SubWise</h1><p>Your bank connection can continue in the SubWise app.</p></main>"));
  app.get("/household/invite/:token", async (request, reply) => {
    try {
      const { token } = request.params as { token: string };
      const payload = verifyHouseholdInviteToken(token, config.ACCESS_TOKEN_SECRET);
      const member = await app.db.householdMember.findUnique({ where: { id: payload.memberId }, include: { household: true } });
      if (!member || member.userId) throw new Error("Invitation unavailable");
      return reply.type("text/html; charset=utf-8").send(`<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>SubWise household invitation</title><main style="font:17px/1.55 -apple-system;max-width:560px;margin:60px auto;padding:24px;color:#10231d"><div style="padding:30px;border:1px solid #dce7e2;border-radius:24px"><p style="color:#0d9960;font-weight:700">SUBWISE HOUSEHOLD</p><h1>You’re invited.</h1><p>Open this link on an iPhone with SubWise installed to join <strong>${escapeHTML(member.household.name)}</strong>.</p><p style="color:#5f7069">The invitation expires in seven days. Ask the sender for a new link if this one is no longer active.</p></div></main>`);
    } catch {
      return reply.status(404).type("text/html; charset=utf-8").send("<!doctype html><meta name='viewport' content='width=device-width'><title>Invitation unavailable</title><main style='font:17px -apple-system;max-width:520px;margin:60px auto;padding:24px'><h1>Invitation unavailable</h1><p>This link is invalid, expired, or already used. Ask the sender for a new invitation.</p></main>");
    }
  });
  app.register(legalRoutes);
  app.register(async (api) => {
    await api.register(authRoutes);
    await api.register(userRoutes);
    await api.register(dashboardRoutes);
    await api.register(subscriptionRoutes);
    await api.register(optimizationRoutes);
    await api.register(savingsRoutes);
    await api.register(householdRoutes);
    await api.register(agentRoutes);
    await api.register(trialRoutes);
    await api.register(cancellationRoutes);
    await api.register(discoveryRoutes);
  }, { prefix: "/api/v1" });
  return app;
}
