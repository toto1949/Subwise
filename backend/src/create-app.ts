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
    applinks: { details: [{ appIDs: ["3K82B6HTAT.com.toto.Subwise"], components: [{ "/": "/plaid/*", comment: "Plaid OAuth return links" }] }] }
  }));
  app.get("/plaid/oauth", async (_request, reply) => reply.type("text/html").send("<!doctype html><meta name='viewport' content='width=device-width'><title>Return to SubWise</title><main style='font:16px -apple-system;padding:40px;max-width:520px;margin:auto'><h1>Return to SubWise</h1><p>Your bank connection can continue in the SubWise app.</p></main>"));
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
