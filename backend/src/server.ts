import { buildApp } from "./create-app.js";
import { loadConfig } from "./config.js";

const config = loadConfig();
const app = await buildApp(config);
const close = async () => { await app.close(); process.exit(0); };
process.on("SIGINT", close);
process.on("SIGTERM", close);
try { await app.listen({ port: config.PORT, host: "0.0.0.0" }); }
catch (error) { app.log.fatal({ err: error }, "Failed to start API"); process.exit(1); }
