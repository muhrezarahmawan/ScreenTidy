import "dotenv/config";

function intEnv(name: string, fallback: number): number {
  const raw = process.env[name];
  if (raw === undefined || raw === "") return fallback;
  const n = Number.parseInt(raw, 10);
  if (!Number.isFinite(n) || n <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }
  return n;
}

function strEnv(name: string, fallback: string): string {
  const raw = process.env[name];
  if (raw === undefined || raw === "") return fallback;
  return raw;
}

export const PROMPT_VERSION = "screentidy-org-v3";
export const PROVIDER = "openai";

export type AppConfig = {
  /** Listen host — `0.0.0.0` for containers / LAN DEBUG. */
  host: string;
  port: number;
  openaiApiKey: string | undefined;
  openaiModel: string;
  requestTimeoutMs: number;
  maxBatchSize: number;
  imageLongEdgeMax: number;
  schemaVersion: string;
  /**
   * Shared secret for `Authorization: Bearer …` on `/v1/understand*`.
   * NOT the OpenAI API key. Required when running on Railway.
   */
  gatewaySharedSecret: string | undefined;
  /** Simple in-memory rate limit window. */
  rateLimitWindowMs: number;
  rateLimitMaxRequests: number;
};

export function loadConfig(): AppConfig {
  const onRailway = Boolean(process.env.RAILWAY_ENVIRONMENT || process.env.RAILWAY_PROJECT_ID);
  const gatewaySharedSecret = process.env.GATEWAY_SHARED_SECRET?.trim() || undefined;

  if (onRailway && !gatewaySharedSecret) {
    throw new Error(
      "GATEWAY_SHARED_SECRET is required on Railway (MVP/TestFlight bearer token — not OPENAI_API_KEY)"
    );
  }

  return {
    host: strEnv("HOST", "0.0.0.0"),
    // Railway injects PORT; default 8787 for local.
    port: intEnv("PORT", 8787),
    openaiApiKey: process.env.OPENAI_API_KEY?.trim() || undefined,
    openaiModel: strEnv("OPENAI_MODEL", "gpt-5.6-terra"),
    requestTimeoutMs: intEnv("REQUEST_TIMEOUT_MS", 60_000),
    maxBatchSize: intEnv("MAX_BATCH_SIZE", 8),
    imageLongEdgeMax: intEnv("IMAGE_LONG_EDGE_MAX", 1024),
    schemaVersion: strEnv("SCHEMA_VERSION", "screentidy-understanding-v2"),
    gatewaySharedSecret,
    rateLimitWindowMs: intEnv("RATE_LIMIT_WINDOW_MS", 60_000),
    rateLimitMaxRequests: intEnv("RATE_LIMIT_MAX_REQUESTS", 30),
  };
}

export function requireApiKey(config: AppConfig): string {
  if (!config.openaiApiKey) {
    throw new Error("OPENAI_API_KEY is required");
  }
  return config.openaiApiKey;
}
