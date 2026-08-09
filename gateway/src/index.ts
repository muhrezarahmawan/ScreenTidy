import express from "express";
import { createSimpleRateLimiter, requireGatewayAuth } from "./auth.js";
import { loadConfig } from "./config.js";
import { healthHandler, understandBatchHandler, understandHandler } from "./handlers.js";
import { logError, logInfo } from "./logger.js";
import { createOpenAIClient } from "./openaiClient.js";

const config = loadConfig();
const app = express();

// Bound JSON body size; images are base64 so allow a few MB in-memory only.
app.use(express.json({ limit: "8mb" }));
app.disable("x-powered-by");

const client = config.openaiApiKey ? createOpenAIClient(config) : null;
const rateLimit = createSimpleRateLimiter({
  windowMs: config.rateLimitWindowMs,
  maxRequests: config.rateLimitMaxRequests,
});
const gatewayAuth = requireGatewayAuth(config);

app.get("/health", healthHandler(config));

app.post(
  "/v1/understand",
  rateLimit,
  gatewayAuth,
  understandHandler(config, client)
);
app.post(
  "/v1/understand-batch",
  rateLimit,
  gatewayAuth,
  understandBatchHandler(config, client)
);

app.use((_req, res) => {
  res.status(404).json({ error: { code: "NOT_FOUND", message: "Not found" } });
});

app.listen(config.port, config.host, () => {
  logInfo("ScreenTidy gateway listening", {
    host: config.host,
    port: config.port,
    model: config.openaiModel,
    schemaVersion: config.schemaVersion,
    modelConfigured: Boolean(config.openaiApiKey),
    gatewayAuthRequired: Boolean(config.gatewaySharedSecret),
  });
  if (!config.openaiApiKey) {
    logError("OPENAI_API_KEY missing — /health ok, understand routes return 503");
  }
});
