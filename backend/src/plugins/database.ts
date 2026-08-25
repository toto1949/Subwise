import fp from "fastify-plugin";
import { PrismaClient } from "@prisma/client";

declare module "fastify" { interface FastifyInstance { db: PrismaClient } }

export default fp(async (app) => {
  const db = new PrismaClient();
  await db.$connect();
  app.decorate("db", db);
  app.addHook("onClose", async () => { await db.$disconnect(); });
});
