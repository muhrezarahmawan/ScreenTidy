import { APIError } from "openai";

/** Safe upstream fields — never include API keys, images, or OCR. */
export type SanitizedUpstreamError = {
  httpStatus?: number;
  type?: string;
  code?: string;
  /** Truncated, redacted OpenAI message. */
  message?: string;
  param?: string;
  requestId?: string;
};

const SECRET_FRAGMENT = /(sk-[a-zA-Z0-9_-]{8,}|Bearer\s+\S+|api[_-]?key)/gi;

export function sanitizeUpstreamMessage(raw: string | undefined | null): string | undefined {
  if (!raw) return undefined;
  const cleaned = raw.replace(SECRET_FRAGMENT, "[redacted]").replace(/\s+/g, " ").trim();
  if (!cleaned) return undefined;
  return cleaned.length > 280 ? `${cleaned.slice(0, 277)}…` : cleaned;
}

export function extractSanitizedUpstreamError(err: unknown): SanitizedUpstreamError | undefined {
  if (!err || typeof err !== "object") return undefined;

  if (err instanceof APIError) {
    const body = err.error as
      | { message?: string; type?: string; code?: string | number; param?: string }
      | undefined;
    return {
      httpStatus: typeof err.status === "number" ? err.status : undefined,
      type: body?.type ?? err.type,
      code: body?.code != null ? String(body.code) : err.code ?? undefined,
      message: sanitizeUpstreamMessage(body?.message ?? err.message),
      param: body?.param ?? err.param ?? undefined,
      requestId: err.request_id ?? undefined,
    };
  }

  const status = (err as { status?: unknown }).status;
  const message = (err as { message?: unknown }).message;
  if (typeof status === "number" || typeof message === "string") {
    return {
      httpStatus: typeof status === "number" ? status : undefined,
      message: typeof message === "string" ? sanitizeUpstreamMessage(message) : undefined,
    };
  }
  return undefined;
}
