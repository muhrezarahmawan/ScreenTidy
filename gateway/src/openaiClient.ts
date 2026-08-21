import OpenAI, { APIError } from "openai";
import type { AppConfig } from "./config.js";
import { PROMPT_VERSION, PROVIDER, requireApiKey } from "./config.js";
import {
  CONTENT_PROMPT_VERSION,
  CONTENT_SCHEMA_VERSION,
  CONTENT_SYSTEM_PROMPT,
} from "./contentPrompt.js";
import {
  GROUP_PROMPT_VERSION,
  GROUP_SYSTEM_PROMPT,
} from "./groupPrompt.js";
import { finalizeGroupUnderstanding } from "./groupValidation.js";
import { SYSTEM_PROMPT } from "./prompt.js";
import {
  BatchUnderstandingContentSchema,
  ContentUnderstandingContentSchema,
  OPENAI_BATCH_JSON_SCHEMA,
  OPENAI_CONTENT_JSON_SCHEMA,
  OPENAI_GROUP_JSON_SCHEMA,
  OPENAI_SINGLE_JSON_SCHEMA,
  UnderstandingContentSchema,
  type BatchUnderstandingResponse,
  type ContentUnderstandingResponse,
  type GroupUnderstandingResponse,
  type UnderstandingResponse,
} from "./schemas.js";
import {
  extractSanitizedUpstreamError,
  sanitizeUpstreamMessage,
  type SanitizedUpstreamError,
} from "./upstreamError.js";

export class GatewayError extends Error {
  status: number;
  code: string;
  upstream?: SanitizedUpstreamError;
  constructor(status: number, code: string, message: string, upstream?: SanitizedUpstreamError) {
    super(message);
    this.status = status;
    this.code = code;
    this.upstream = upstream;
  }
}

type ContentPart =
  | { type: "input_text"; text: string }
  | { type: "input_image"; image_url: string; detail: "auto" | "low" | "high" };

export function createOpenAIClient(config: AppConfig): OpenAI {
  return new OpenAI({
    apiKey: requireApiKey(config),
    timeout: config.requestTimeoutMs,
  });
}

export async function understandSingle(args: {
  client: OpenAI;
  config: AppConfig;
  userText: string;
  imageDataUrl?: string;
}): Promise<UnderstandingResponse> {
  const content: ContentPart[] = [{ type: "input_text", text: args.userText }];
  if (args.imageDataUrl) {
    content.push({ type: "input_image", image_url: args.imageDataUrl, detail: "auto" });
  }

  const raw = await callResponses({
    client: args.client,
    model: args.config.openaiModel,
    timeoutMs: args.config.requestTimeoutMs,
    systemPrompt: SYSTEM_PROMPT,
    schemaName: "screentidy_understanding_single",
    schema: OPENAI_SINGLE_JSON_SCHEMA,
    content,
  });

  const parsed = UnderstandingContentSchema.safeParse(raw);
  if (!parsed.success) {
    throw new GatewayError(
      422,
      "MODEL_OUTPUT_INVALID",
      "Model output failed server-side validation"
    );
  }

  return {
    ...parsed.data,
    provider: PROVIDER,
    promptVersion: PROMPT_VERSION,
    schemaVersion: args.config.schemaVersion,
  };
}

export async function contentUnderstandSingle(args: {
  client: OpenAI;
  config: AppConfig;
  userText: string;
  imageDataUrl: string;
}): Promise<ContentUnderstandingResponse> {
  const content: ContentPart[] = [
    { type: "input_text", text: args.userText },
    { type: "input_image", image_url: args.imageDataUrl, detail: "auto" },
  ];

  const raw = await callResponses({
    client: args.client,
    model: args.config.openaiModel,
    timeoutMs: args.config.requestTimeoutMs,
    systemPrompt: CONTENT_SYSTEM_PROMPT,
    schemaName: "screentidy_content_understanding_8_3a",
    schema: OPENAI_CONTENT_JSON_SCHEMA,
    content,
  });

  const parsed = ContentUnderstandingContentSchema.safeParse(raw);
  if (!parsed.success) {
    throw new GatewayError(
      422,
      "MODEL_OUTPUT_INVALID",
      "Content understanding output failed server-side validation"
    );
  }

  const banned = /\b(create collection|reuse collection|collection title|proposedNewCollection)\b/i;
  for (const note of parsed.data.evidenceNotes) {
    if (banned.test(note)) {
      throw new GatewayError(
        422,
        "MODEL_OUTPUT_INVALID",
        "Content understanding must not propose Collections"
      );
    }
  }

  return {
    ...parsed.data,
    provider: PROVIDER,
    promptVersion: CONTENT_PROMPT_VERSION,
    schemaVersion: CONTENT_SCHEMA_VERSION,
  };
}

/** Sprint 8.3B Lab — evidence-only group reasoning. No images. No Collection fields. */
export async function groupUnderstand(args: {
  client: OpenAI;
  config: AppConfig;
  userText: string;
  expectedLocalIds: string[];
}): Promise<GroupUnderstandingResponse> {
  const content: ContentPart[] = [{ type: "input_text", text: args.userText }];

  const raw = await callResponses({
    client: args.client,
    model: args.config.openaiModel,
    timeoutMs: args.config.requestTimeoutMs,
    systemPrompt: GROUP_SYSTEM_PROMPT,
    schemaName: "screentidy_group_understanding_8_3b",
    schema: OPENAI_GROUP_JSON_SCHEMA,
    content,
  });

  const finalized = finalizeGroupUnderstanding({
    raw,
    expectedLocalIds: args.expectedLocalIds,
    provider: PROVIDER,
    promptVersion: GROUP_PROMPT_VERSION,
  });
  if (!finalized.ok) {
    throw new GatewayError(422, finalized.error.code, finalized.error.message);
  }
  return finalized.value;
}

export async function understandBatch(args: {
  client: OpenAI;
  config: AppConfig;
  userText: string;
  imageDataUrls: Array<{ localId: string; dataUrl: string }>;
  expectedLocalIds: string[];
}): Promise<BatchUnderstandingResponse> {
  const content: ContentPart[] = [{ type: "input_text", text: args.userText }];
  for (const img of args.imageDataUrls) {
    content.push({
      type: "input_text",
      text: `Image for member localId=${img.localId}`,
    });
    content.push({ type: "input_image", image_url: img.dataUrl, detail: "auto" });
  }

  const raw = await callResponses({
    client: args.client,
    model: args.config.openaiModel,
    timeoutMs: args.config.requestTimeoutMs,
    systemPrompt: SYSTEM_PROMPT,
    schemaName: "screentidy_understanding_batch",
    schema: OPENAI_BATCH_JSON_SCHEMA,
    content,
  });

  const parsed = BatchUnderstandingContentSchema.safeParse(raw);
  if (!parsed.success) {
    throw new GatewayError(
      422,
      "MODEL_OUTPUT_INVALID",
      "Model batch output failed server-side validation"
    );
  }

  const returnedIds = new Set(parsed.data.members.map((m) => m.localId));
  for (const id of args.expectedLocalIds) {
    if (!returnedIds.has(id)) {
      throw new GatewayError(
        422,
        "MODEL_OUTPUT_INVALID",
        "Model batch output missing one or more member localIds"
      );
    }
  }
  if (parsed.data.members.length !== args.expectedLocalIds.length) {
    throw new GatewayError(
      422,
      "MODEL_OUTPUT_INVALID",
      "Model batch output member count mismatch"
    );
  }

  if (parsed.data.sharedContext) {
    for (const id of parsed.data.sharedContext.memberLocalIds) {
      if (!returnedIds.has(id)) {
        throw new GatewayError(
          422,
          "MODEL_OUTPUT_INVALID",
          "sharedContext references unknown localId"
        );
      }
    }
  }

  for (const id of parsed.data.unresolvedIds) {
    if (!returnedIds.has(id)) {
      throw new GatewayError(
        422,
        "MODEL_OUTPUT_INVALID",
        "unresolvedIds references unknown localId"
      );
    }
  }

  if (parsed.data.sharedContext) {
    const related = new Set(parsed.data.sharedContext.memberLocalIds);
    for (const id of related) {
      if (parsed.data.unresolvedIds.includes(id)) {
        throw new GatewayError(
          422,
          "MODEL_OUTPUT_INVALID",
          "localId cannot be both in sharedContext and unresolvedIds"
        );
      }
    }
  }

  return {
    ...parsed.data,
    provider: PROVIDER,
    promptVersion: PROMPT_VERSION,
    schemaVersion: args.config.schemaVersion,
  };
}

async function callResponses(args: {
  client: OpenAI;
  model: string;
  timeoutMs: number;
  systemPrompt: string;
  schemaName: string;
  schema: Record<string, unknown> | object;
  content: ContentPart[];
}): Promise<unknown> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), args.timeoutMs);

  try {
    // Prefer `instructions` for system policy; user turn carries OCR/image evidence.
    // max_output_tokens keeps GPT-5.x reasoning models from returning empty visible text.
    const response = await args.client.responses.create(
      {
        model: args.model,
        instructions: args.systemPrompt,
        input: [
          {
            role: "user",
            content: args.content,
          },
        ],
        max_output_tokens: 4096,
        text: {
          format: {
            type: "json_schema",
            name: args.schemaName,
            strict: true,
            schema: args.schema as Record<string, unknown>,
          },
        },
      },
      { signal: controller.signal }
    );

    const text = response.output_text;
    if (!text || !text.trim()) {
      throw new GatewayError(422, "MODEL_OUTPUT_EMPTY", "Model returned empty output");
    }

    let json: unknown;
    try {
      json = JSON.parse(text);
    } catch {
      throw new GatewayError(422, "MODEL_OUTPUT_INVALID", "Model output was not valid JSON");
    }
    return json;
  } catch (err) {
    if (err instanceof GatewayError) throw err;
    if (isAbortError(err)) {
      throw new GatewayError(504, "UPSTREAM_TIMEOUT", "OpenAI request timed out");
    }
    throw mapOpenAIFailure(err);
  } finally {
    clearTimeout(timer);
  }
}

export function mapOpenAIFailure(err: unknown): GatewayError {
  const upstream = extractSanitizedUpstreamError(err);
  const status = upstream?.httpStatus;

  if (status === 401) {
    return new GatewayError(
      502,
      "UPSTREAM_AUTH",
      "OpenAI authentication failed — check OPENAI_API_KEY on Railway",
      upstream
    );
  }
  if (status === 403) {
    return new GatewayError(
      502,
      "UPSTREAM_PERMISSION",
      "OpenAI denied access to this model or project",
      upstream
    );
  }
  if (status === 404) {
    return new GatewayError(
      502,
      "UPSTREAM_MODEL_NOT_FOUND",
      "OpenAI model not found — check OPENAI_MODEL",
      upstream
    );
  }
  if (status === 429) {
    return new GatewayError(502, "UPSTREAM_RATE_LIMIT", "OpenAI rate limit exceeded", upstream);
  }
  if (typeof status === "number" && status >= 400 && status < 500) {
    return new GatewayError(
      502,
      "UPSTREAM_CLIENT_ERROR",
      sanitizeUpstreamMessage(upstream?.message) ?? "OpenAI rejected the request",
      upstream
    );
  }
  if (err instanceof APIError) {
    return new GatewayError(
      502,
      "UPSTREAM_ERROR",
      sanitizeUpstreamMessage(err.message) ?? "OpenAI request failed",
      upstream
    );
  }
  return new GatewayError(502, "UPSTREAM_ERROR", "OpenAI request failed", upstream);
}

function isAbortError(err: unknown): boolean {
  if (!err || typeof err !== "object") return false;
  const name = (err as { name?: string }).name;
  return name === "AbortError" || name === "APIUserAbortError";
}
