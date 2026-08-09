import type { NextFunction, Request, Response } from "express";
import type { AppConfig } from "./config.js";
import { timingSafeEqualString } from "./security.js";

/** Require `Authorization: Bearer <GATEWAY_SHARED_SECRET>` on cost-bearing routes. */
export function requireGatewayAuth(config: AppConfig) {
  return (req: Request, res: Response, next: NextFunction): void => {
    if (!config.gatewaySharedSecret) {
      // Local/dev without a secret is allowed; Railway boot refuses empty secret.
      next();
      return;
    }

    const header = req.header("authorization") ?? "";
    const match = /^Bearer\s+(.+)$/i.exec(header.trim());
    const presented = match?.[1]?.trim() ?? "";
    if (!presented || !timingSafeEqualString(presented, config.gatewaySharedSecret)) {
      res.status(401).json({
        error: {
          code: "UNAUTHORIZED",
          message: "Missing or invalid gateway bearer token",
        },
      });
      return;
    }
    next();
  };
}

/**
 * Tiny in-memory rate limiter (per client IP). Enough for Sprint 8 / TestFlight;
 * not a production WAF.
 */
export function createSimpleRateLimiter(args: {
  windowMs: number;
  maxRequests: number;
}) {
  const hits = new Map<string, number[]>();

  return (req: Request, res: Response, next: NextFunction): void => {
    const now = Date.now();
    const key =
      (typeof req.headers["x-forwarded-for"] === "string"
        ? req.headers["x-forwarded-for"].split(",")[0]?.trim()
        : undefined) ||
      req.socket.remoteAddress ||
      "unknown";

    const windowStart = now - args.windowMs;
    const recent = (hits.get(key) ?? []).filter((t) => t >= windowStart);
    if (recent.length >= args.maxRequests) {
      res.status(429).json({
        error: {
          code: "RATE_LIMITED",
          message: "Too many requests — try again shortly",
        },
      });
      return;
    }
    recent.push(now);
    hits.set(key, recent);

    // Opportunistic cleanup to avoid unbounded growth.
    if (hits.size > 5_000) {
      for (const [k, times] of hits) {
        const kept = times.filter((t) => t >= windowStart);
        if (kept.length === 0) hits.delete(k);
        else hits.set(k, kept);
      }
    }
    next();
  };
}
