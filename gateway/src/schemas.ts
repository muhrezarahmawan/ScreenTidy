import { z } from "zod";

const confidence = z.number().min(0).max(1);
const nonEmptyString = z.string().min(1);

export const EligibleCollectionSchema = z.object({
  title: nonEmptyString,
  aliases: z.array(z.string()).optional(),
  keyEntities: z.array(z.string()).optional(),
  keyTerms: z.array(z.string()).optional(),
  visualDescriptors: z.array(z.string()).optional(),
  dateRangeStart: z.string().optional(),
  dateRangeEnd: z.string().optional(),
});

export const EntitySchema = z.object({
  type: nonEmptyString,
  value: nonEmptyString,
  confidence,
});

export const CandidateCollectionSchema = z.object({
  title: nonEmptyString,
  confidence,
  reasonSignals: z.array(z.string()),
});

export const ProposedNewCollectionSchema = z.object({
  title: nonEmptyString,
  emoji: z.string(),
  confidence,
});

/** Model content fields (metadata added by gateway). */
export const UnderstandingContentSchema = z.object({
  summary: z.string(),
  typeFacets: z.array(z.string()),
  entities: z.array(EntitySchema),
  locations: z.array(z.string()),
  dates: z.array(z.string()),
  visualDescriptors: z.array(z.string()),
  candidateCollections: z.array(CandidateCollectionSchema),
  proposedNewCollection: ProposedNewCollectionSchema.nullable(),
  reasonSignals: z.array(z.string()),
});

export const UnderstandingResponseSchema = UnderstandingContentSchema.extend({
  provider: nonEmptyString,
  promptVersion: nonEmptyString,
  schemaVersion: nonEmptyString,
});

export const SharedContextSchema = z.object({
  title: nonEmptyString,
  confidence,
  memberLocalIds: z.array(nonEmptyString).min(1),
  evidence: z.array(z.string()).default([]),
});

export const BatchMemberResultSchema = UnderstandingContentSchema.extend({
  localId: nonEmptyString,
});

export const BatchUnderstandingContentSchema = z.object({
  members: z.array(BatchMemberResultSchema).min(1),
  sharedContext: SharedContextSchema.nullable(),
  unresolvedIds: z.array(z.string()).default([]),
});

export const BatchUnderstandingResponseSchema = BatchUnderstandingContentSchema.extend({
  provider: nonEmptyString,
  promptVersion: nonEmptyString,
  schemaVersion: nonEmptyString,
});

export const UnderstandRequestSchema = z.object({
  correlationId: nonEmptyString,
  schemaVersion: z.string().optional(),
  ocrNormalized: z.string().optional(),
  createdAt: z.string().optional(),
  imageBase64: z.string().optional(),
  imageMimeType: z.string().optional(),
  eligibleCollections: z.array(EligibleCollectionSchema).default([]),
  allowVisual: z.boolean(),
});

export const BatchMemberRequestSchema = z.object({
  localId: nonEmptyString,
  ocrNormalized: z.string().optional(),
  createdAt: z.string().optional(),
  imageBase64: z.string().optional(),
  imageMimeType: z.string().optional(),
  /** Optional compact Level 2A facets — evidence only, never Collection titles. */
  visualFacets: z.array(z.string()).optional(),
  sourcePlatform: z.string().optional(),
  contentType: z.string().optional(),
  contentFamily: z.string().optional(),
});

export const UnderstandBatchRequestSchema = z.object({
  correlationId: nonEmptyString,
  schemaVersion: z.string().optional(),
  allowVisual: z.boolean(),
  eligibleCollections: z.array(EligibleCollectionSchema).default([]),
  members: z.array(BatchMemberRequestSchema).min(1),
});

export type UnderstandRequest = z.infer<typeof UnderstandRequestSchema>;
export type UnderstandBatchRequest = z.infer<typeof UnderstandBatchRequestSchema>;
export type UnderstandingResponse = z.infer<typeof UnderstandingResponseSchema>;
export type BatchUnderstandingResponse = z.infer<typeof BatchUnderstandingResponseSchema>;
export type UnderstandingContent = z.infer<typeof UnderstandingContentSchema>;

/** OpenAI strict JSON Schema for a single understanding result. */
export const OPENAI_SINGLE_JSON_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "summary",
    "typeFacets",
    "entities",
    "locations",
    "dates",
    "visualDescriptors",
    "candidateCollections",
    "proposedNewCollection",
    "reasonSignals",
  ],
  properties: {
    summary: { type: "string" },
    typeFacets: { type: "array", items: { type: "string" } },
    entities: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["type", "value", "confidence"],
        properties: {
          type: { type: "string" },
          value: { type: "string" },
          confidence: { type: "number" },
        },
      },
    },
    locations: { type: "array", items: { type: "string" } },
    dates: { type: "array", items: { type: "string" } },
    visualDescriptors: { type: "array", items: { type: "string" } },
    candidateCollections: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["title", "confidence", "reasonSignals"],
        properties: {
          title: { type: "string" },
          confidence: { type: "number" },
          reasonSignals: { type: "array", items: { type: "string" } },
        },
      },
    },
    proposedNewCollection: {
      anyOf: [
        {
          type: "object",
          additionalProperties: false,
          required: ["title", "emoji", "confidence"],
          properties: {
            title: { type: "string" },
            emoji: { type: "string" },
            confidence: { type: "number" },
          },
        },
        { type: "null" },
      ],
    },
    reasonSignals: { type: "array", items: { type: "string" } },
  },
} as const;

export const OPENAI_BATCH_JSON_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["members", "sharedContext", "unresolvedIds"],
  properties: {
    members: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "localId",
          "summary",
          "typeFacets",
          "entities",
          "locations",
          "dates",
          "visualDescriptors",
          "candidateCollections",
          "proposedNewCollection",
          "reasonSignals",
        ],
        properties: {
          localId: { type: "string" },
          summary: { type: "string" },
          typeFacets: { type: "array", items: { type: "string" } },
          entities: {
            type: "array",
            items: {
              type: "object",
              additionalProperties: false,
              required: ["type", "value", "confidence"],
              properties: {
                type: { type: "string" },
                value: { type: "string" },
                confidence: { type: "number" },
              },
            },
          },
          locations: { type: "array", items: { type: "string" } },
          dates: { type: "array", items: { type: "string" } },
          visualDescriptors: { type: "array", items: { type: "string" } },
          candidateCollections: {
            type: "array",
            items: {
              type: "object",
              additionalProperties: false,
              required: ["title", "confidence", "reasonSignals"],
              properties: {
                title: { type: "string" },
                confidence: { type: "number" },
                reasonSignals: { type: "array", items: { type: "string" } },
              },
            },
          },
          proposedNewCollection: {
            anyOf: [
              {
                type: "object",
                additionalProperties: false,
                required: ["title", "emoji", "confidence"],
                properties: {
                  title: { type: "string" },
                  emoji: { type: "string" },
                  confidence: { type: "number" },
                },
              },
              { type: "null" },
            ],
          },
          reasonSignals: { type: "array", items: { type: "string" } },
        },
      },
    },
    sharedContext: {
      anyOf: [
        {
          type: "object",
          additionalProperties: false,
          required: ["title", "confidence", "memberLocalIds", "evidence"],
          properties: {
            title: { type: "string" },
            confidence: { type: "number" },
            memberLocalIds: { type: "array", items: { type: "string" } },
            evidence: { type: "array", items: { type: "string" } },
          },
        },
        { type: "null" },
      ],
    },
    unresolvedIds: { type: "array", items: { type: "string" } },
  },
} as const;

// --- Sprint 8.3A content understanding (no Collection fields) ---

const labeledIdConfidence = z.object({
  id: nonEmptyString,
  confidence,
});

export const EmbeddedHintSchema = z.object({
  id: nonEmptyString,
  kind: z.enum(["notification", "widget", "other"]),
  confidence,
});

export const ContentUnderstandingContentSchema = z.object({
  surface: labeledIdConfidence,
  platform: labeledIdConfidence,
  contentType: labeledIdConfidence,
  contentFamily: labeledIdConfidence,
  embeddedHints: z.array(EmbeddedHintSchema),
  openDescriptors: z.array(z.string().max(80)).max(12),
  evidenceNotes: z.array(z.string().max(200)).max(8),
  disagreesWithLocal: z.boolean(),
});

export const ContentUnderstandingResponseSchema = ContentUnderstandingContentSchema.extend({
  provider: nonEmptyString,
  promptVersion: nonEmptyString,
  schemaVersion: nonEmptyString,
});

export const ContentUnderstandRequestSchema = z.object({
  correlationId: nonEmptyString,
  schemaVersion: z.string().optional(),
  createdAt: z.string().optional(),
  imageBase64: nonEmptyString,
  imageMimeType: z.string().optional(),
  localEvidence: z.record(z.unknown()).default({}),
});

export type ContentUnderstandRequest = z.infer<typeof ContentUnderstandRequestSchema>;
export type ContentUnderstandingResponse = z.infer<typeof ContentUnderstandingResponseSchema>;
export type ContentUnderstandingContent = z.infer<typeof ContentUnderstandingContentSchema>;

const labeledIdConfidenceOpenAI = {
  type: "object",
  additionalProperties: false,
  required: ["id", "confidence"],
  properties: {
    id: { type: "string" },
    confidence: { type: "number" },
  },
} as const;

export const OPENAI_CONTENT_JSON_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "surface",
    "platform",
    "contentType",
    "contentFamily",
    "embeddedHints",
    "openDescriptors",
    "evidenceNotes",
    "disagreesWithLocal",
  ],
  properties: {
    surface: labeledIdConfidenceOpenAI,
    platform: labeledIdConfidenceOpenAI,
    contentType: labeledIdConfidenceOpenAI,
    contentFamily: labeledIdConfidenceOpenAI,
    embeddedHints: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["id", "kind", "confidence"],
        properties: {
          id: { type: "string" },
          kind: { type: "string", enum: ["notification", "widget", "other"] },
          confidence: { type: "number" },
        },
      },
    },
    openDescriptors: { type: "array", items: { type: "string" } },
    evidenceNotes: { type: "array", items: { type: "string" } },
    disagreesWithLocal: { type: "boolean" },
  },
} as const;
