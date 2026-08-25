import { z } from "zod";

const schema = z.object({
  NODE_ENV: z.enum(["local", "development", "test", "staging", "production"]).default("development"),
  PORT: z.coerce.number().int().positive().default(3000),
  DATABASE_URL: z.string().url(),
  ACCESS_TOKEN_SECRET: z.string().min(32),
  APPLE_CLIENT_ID: z.string().min(3),
  OPENAI_API_KEY: z.string().optional(),
  OPENAI_MODEL: z.string().default("gpt-5-mini"),
  LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace", "silent"]).default("info")
});

export type Config = z.infer<typeof schema>;
export function loadConfig(environment: NodeJS.ProcessEnv = process.env): Config {
  return schema.parse(environment);
}
