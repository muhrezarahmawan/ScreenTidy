import type { Request, Response } from "express";
import type OpenAI from "openai";
import type { AppConfig } from "./config.js";
import { CONTENT_SCHEMA_VERSION, buildContentUserPrompt } from "./contentPrompt.js";
import {
  assertImageWithinBounds,
  decodeBase64Image,
  ImageValidationError,
  probeImage,
  toDataUrl,
} from "./image.js";
import { logRequest } from "./logger.js";
import {
  GatewayError,
  contentUnderstandSingle,
  understandBatch,
  understandSingle,
} from "./openaiClient.js";
import { buildBatchUserPrompt, buildSingleUserPrompt } from "./prompt.js";
import {
  ContentUnderstandRequestSchema,
  UnderstandBatchRequestSchema,
  UnderstandRequestSchema,
} from "./schemas.js";

export function healthHandler(config: AppConfig) {
  return (_req: Request, res: Response): void => {
    res.json({
      ok: true,
      schemaVersion: config.schemaVersion,
      contentSchemaVersion: CONTENT_SCHEMA_VERSION,
      modelConfigured: Boolean(config.openaiApiKey),
    });
  };
}

export function understandHandler(config: AppConfig, client: OpenAI | null) {
  return async (req: Request, res: Response): Promise<void> => {
    const started = Date.now();
    let correlationId = "unknown";
    let status = 500;
    let errorCode: string | undefined;

    try {
      correlationId = peekCorrelationId(req.body);

      const parsed = UnderstandRequestSchema.safeParse(req.body);
      if (!parsed.success) {
        throw new GatewayError(400, "REQUEST_INVALID", "Invalid request body");
      }
      const body = parsed.data;
      correlationId = body.correlationId;
      ensureClient(client, config);

      if (body.schemaVersion && body.schemaVersion !== config.schemaVersion) {
        throw new GatewayError(
          422,
          "SCHEMA_VERSION_MISMATCH",
          `Expected schemaVersion ${config.schemaVersion}`
        );
      }

      const prepared = prepareVisual({
        allowVisual: body.allowVisual,
        imageBase64: body.imageBase64,
        imageMimeType: body.imageMimeType,
        ocrNormalized: body.ocrNormalized,
        longEdgeMax: config.imageLongEdgeMax,
      });

      const userText = buildSingleUserPrompt({
        ocrNormalized: body.ocrNormalized,
        createdAt: body.createdAt,
        eligibleCollections: body.eligibleCollections,
        allowVisual: body.allowVisual,
        hasImage: Boolean(prepared.dataUrl),
      });

      const result = await understandSingle({
        client: client!,
        config,
        userText,
        imageDataUrl: prepared.dataUrl,
      });

      status = 200;
      res.json(result);
    } catch (err) {
      const mapped = mapError(err);
      status = mapped.status;
      errorCode = mapped.code;
      res.status(mapped.status).json({
        error: {
          code: mapped.code,
          message: mapped.message,
          correlationId,
        },
      });
    } finally {
      logRequest({
        route: "/v1/understand",
        correlationId,
        status,
        latencyMs: Date.now() - started,
        model: config.openaiModel,
        errorCode,
      });
    }
  };
}

export function understandBatchHandler(config: AppConfig, client: OpenAI | null) {
  return async (req: Request, res: Response): Promise<void> => {
    const started = Date.now();
    let correlationId = "unknown";
    let status = 500;
    let errorCode: string | undefined;

    try {
      correlationId = peekCorrelationId(req.body);

      const parsed = UnderstandBatchRequestSchema.safeParse(req.body);
      if (!parsed.success) {
        throw new GatewayError(400, "REQUEST_INVALID", "Invalid request body");
      }
      const body = parsed.data;
      correlationId = body.correlationId;
      ensureClient(client, config);

      if (body.schemaVersion && body.schemaVersion !== config.schemaVersion) {
        throw new GatewayError(
          422,
          "SCHEMA_VERSION_MISMATCH",
          `Expected schemaVersion ${config.schemaVersion}`
        );
      }

      if (body.members.length > config.maxBatchSize) {
        throw new GatewayError(
          422,
          "BATCH_TOO_LARGE",
          `Batch exceeds MAX_BATCH_SIZE (${config.maxBatchSize})`
        );
      }

      const localIds = body.members.map((m) => m.localId);
      if (new Set(localIds).size !== localIds.length) {
        throw new GatewayError(400, "REQUEST_INVALID", "Duplicate member localId values");
      }

      const imageDataUrls: Array<{ localId: string; dataUrl: string }> = [];
      const memberMeta = body.members.map((m) => {
        const prepared = prepareVisual({
          allowVisual: body.allowVisual,
          imageBase64: m.imageBase64,
          imageMimeType: m.imageMimeType,
          ocrNormalized: m.ocrNormalized,
          longEdgeMax: config.imageLongEdgeMax,
        });
        if (prepared.dataUrl) {
          imageDataUrls.push({ localId: m.localId, dataUrl: prepared.dataUrl });
        }
        return {
          localId: m.localId,
          ocrNormalized: m.ocrNormalized,
          createdAt: m.createdAt,
          hasImage: Boolean(prepared.dataUrl),
          visualFacets: m.visualFacets,
          sourcePlatform: m.sourcePlatform,
          contentType: m.contentType,
          contentFamily: m.contentFamily,
        };
      });

      const userText = buildBatchUserPrompt({
        members: memberMeta,
        eligibleCollections: body.eligibleCollections,
        allowVisual: body.allowVisual,
      });

      const result = await understandBatch({
        client: client!,
        config,
        userText,
        imageDataUrls,
        expectedLocalIds: localIds,
      });

      status = 200;
      res.json(result);
    } catch (err) {
      const mapped = mapError(err);
      status = mapped.status;
      errorCode = mapped.code;
      res.status(mapped.status).json({
        error: {
          code: mapped.code,
          message: mapped.message,
          correlationId,
        },
      });
    } finally {
      logRequest({
        route: "/v1/understand-batch",
        correlationId,
        status,
        latencyMs: Date.now() - started,
        model: config.openaiModel,
        errorCode,
      });
    }
  };
}

export function contentUnderstandHandler(config: AppConfig, client: OpenAI | null) {
  return async (req: Request, res: Response): Promise<void> => {
    const started = Date.now();
    let correlationId = "unknown";
    let status = 500;
    let errorCode: string | undefined;

    try {
      correlationId = peekCorrelationId(req.body);

      const parsed = ContentUnderstandRequestSchema.safeParse(req.body);
      if (!parsed.success) {
        throw new GatewayError(400, "REQUEST_INVALID", "Invalid content-understand request body");
      }
      const body = parsed.data;
      correlationId = body.correlationId;
      ensureClient(client, config);

      if (body.schemaVersion && body.schemaVersion !== CONTENT_SCHEMA_VERSION) {
        throw new GatewayError(
          422,
          "SCHEMA_VERSION_MISMATCH",
          `Expected schemaVersion ${CONTENT_SCHEMA_VERSION}`
        );
      }

      // Image is required and authoritative for 8.3A Lab.
      let dataUrl: string;
      try {
        const buffer = decodeBase64Image(body.imageBase64);
        const probe = probeImage(buffer, body.imageMimeType);
        assertImageWithinBounds(probe, config.imageLongEdgeMax);
        dataUrl = toDataUrl(probe.mimeType, buffer);
      } catch (err) {
        if (err instanceof ImageValidationError) {
          throw new GatewayError(422, err.code, err.message);
        }
        throw err;
      }

      const userText = buildContentUserPrompt({
        createdAt: body.createdAt,
        localEvidence: body.localEvidence,
        hasImage: true,
      });

      const result = await contentUnderstandSingle({
        client: client!,
        config,
        userText,
        imageDataUrl: dataUrl,
      });

      status = 200;
      res.json(result);
    } catch (err) {
      const mapped = mapError(err);
      status = mapped.status;
      errorCode = mapped.code;
      res.status(mapped.status).json({
        error: {
          code: mapped.code,
          message: mapped.message,
          correlationId,
        },
      });
    } finally {
      logRequest({
        route: "/v1/content-understand",
        correlationId,
        status,
        latencyMs: Date.now() - started,
        model: config.openaiModel,
        errorCode,
      });
    }
  };
}

function peekCorrelationId(body: unknown): string {
  if (body && typeof body === "object" && "correlationId" in body) {
    const value = (body as { correlationId?: unknown }).correlationId;
    if (typeof value === "string" && value.trim()) return value;
  }
  return "unknown";
}

function ensureClient(client: OpenAI | null, config: AppConfig): asserts client is OpenAI {
  if (!client || !config.openaiApiKey) {
    throw new GatewayError(503, "MODEL_NOT_CONFIGURED", "OPENAI_API_KEY is not configured");
  }
}

function prepareVisual(args: {
  allowVisual: boolean;
  imageBase64?: string;
  imageMimeType?: string;
  ocrNormalized?: string;
  longEdgeMax: number;
}): { dataUrl?: string } {
  const hasImage = Boolean(args.imageBase64?.trim());

  if (!args.allowVisual) {
    return {};
  }

  if (!hasImage) {
    if (!args.ocrNormalized?.trim()) {
      throw new GatewayError(
        422,
        "VISUAL_REQUIRED",
        "Image required when allowVisual is true and OCR is empty"
      );
    }
    return {};
  }

  try {
    const buffer = decodeBase64Image(args.imageBase64!);
    const probe = probeImage(buffer, args.imageMimeType);
    assertImageWithinBounds(probe, args.longEdgeMax);
    return { dataUrl: toDataUrl(probe.mimeType, buffer) };
  } catch (err) {
    if (err instanceof ImageValidationError) {
      throw new GatewayError(422, err.code, err.message);
    }
    throw err;
  }
}

function mapError(err: unknown): { status: number; code: string; message: string } {
  if (err instanceof GatewayError) {
    return { status: err.status, code: err.code, message: err.message };
  }
  return { status: 500, code: "INTERNAL_ERROR", message: "Unexpected server error" };
}
