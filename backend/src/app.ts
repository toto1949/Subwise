import Fastify from "fastify";
import { loadConfig } from "./config.js";
import { buildApp } from "./create-app.js";

const config = loadConfig();
const app = buildApp(config);

void Fastify;
void app.listen({ port: config.PORT, host: "0.0.0.0" });
