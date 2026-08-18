import OpenAI from "openai";
import type { AppConfig } from "./config.js";
import { PROMPT_VERSION, PROVIDER, requireApiKey } from "./config.js";
import {
  CONTENT_PROMPT_VERSION,
  CONTENT_SCHEMA_VERSION,
  CONTENT_SYSTEM_PROMPT,
} from "./contentPrompt.js";
import { SYSTEM_PROMPT } from "./prompt.js";
import {
  BatchUnderstandingContentSchema,
  ContentUnderstandingContentSchema,
  OPENAI_BATCH_JSON_SCHEMA,
  OPENAI_CONTENT_JSON_SCHEMA,
  OPENAI_SINGLE_JSON_SCHEMA,
  UnderstandingContentSchema,
  type BatchUnderstandingResponse,
  type ContentUnderstandingResponse,
  type UnderstandingResponse,
} from "./schemas.js";

export class GatewayError extends Error {
  status: number;
  code: string;
  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
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
    const response = await args.client.responses.create(
      {
        model: args.model,
        input: [
          {
            role: "system",
            content: [{ type: "input_text", text: args.systemPrompt }],
          },
          {
            role: "user",
            content: args.content,
          },
        ],
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
    const status = (err as { status?: number })?.status;
    if (typeof status === "number" && status >= 400 && status < 500) {
      throw new GatewayError(502, "UPSTREAM_CLIENT_ERROR", "OpenAI rejected the request");
    }
    throw new GatewayError(502, "UPSTREAM_ERROR", "OpenAI request failed");
  } finally {
    clearTimeout(timer);
  }
}

function isAbortError(err: unknown): boolean {
  if (!err || typeof err !== "object") return false;
  const name = (err as { name?: string }).name;
  return name === "AbortError" || name === "APIUserAbortError";
}
