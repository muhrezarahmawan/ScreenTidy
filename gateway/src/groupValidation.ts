import { GROUP_SCHEMA_VERSION } from "./groupPrompt.js";
import {
  GroupUnderstandingContentSchema,
  type GroupUnderstandingContent,
  type GroupUnderstandingResponse,
} from "./schemas.js";

/** Top-level Collection / production-organize leakage keys. */
export const GROUP_FORBIDDEN_TOP_LEVEL_KEYS = [
  "proposedNewCollection",
  "collectionName",
  "collectionTitle",
  "createCollection",
  "reuseCollection",
  "candidateCollections",
  "eligibleCollections",
  "collectionID",
  "collectionId",
  "imageBase64",
  "imageMimeType",
] as const;

const COLLECTION_TEXT_BAN =
  /\b(create collection|reuse collection|collection title|proposedNewCollection|collectionname|collection_title)\b/i;

export type GroupFinalizeError = {
  code:
    | "FORBIDDEN_COLLECTION_FIELDS"
    | "MODEL_OUTPUT_INVALID"
    | "INCONSISTENT_YES_INSUFFICIENT"
    | "UNKNOWN_MEMBER_ID"
    | "MISSING_MEMBER_ASSESSMENT";
  message: string;
};

/**
 * Strict post-model finalize for 8.3b-group-v1.
 * Pure / deterministic — used by the Lab route and offline tests (no OpenAI).
 */
export function finalizeGroupUnderstanding(args: {
  raw: unknown;
  expectedLocalIds: string[];
  provider: string;
  promptVersion: string;
}): { ok: true; value: GroupUnderstandingResponse } | { ok: false; error: GroupFinalizeError } {
  if (!args.raw || typeof args.raw !== "object" || Array.isArray(args.raw)) {
    return {
      ok: false,
      error: { code: "MODEL_OUTPUT_INVALID", message: "Group understanding output is not an object" },
    };
  }

  const dict = args.raw as Record<string, unknown>;
  const presentForbidden = GROUP_FORBIDDEN_TOP_LEVEL_KEYS.filter((k) =>
    Object.prototype.hasOwnProperty.call(dict, k)
  );
  if (presentForbidden.length > 0) {
    return {
      ok: false,
      error: {
        code: "FORBIDDEN_COLLECTION_FIELDS",
        message: `Group understanding must not include: ${presentForbidden.join(", ")}`,
      },
    };
  }

  const parsed = GroupUnderstandingContentSchema.safeParse(args.raw);
  if (!parsed.success) {
    return {
      ok: false,
      error: {
        code: "MODEL_OUTPUT_INVALID",
        message: "Group understanding output failed server-side validation",
      },
    };
  }

  const content = parsed.data;
  const consistency = validateGroupInvariants(content, args.expectedLocalIds);
  if (!consistency.ok) return consistency;

  const textLeak = collectBannedText(content);
  if (textLeak) {
    return {
      ok: false,
      error: {
        code: "FORBIDDEN_COLLECTION_FIELDS",
        message: `Group understanding text must not propose Collections (${textLeak})`,
      },
    };
  }

  return {
    ok: true,
    value: {
      ...content,
      provider: args.provider,
      promptVersion: args.promptVersion,
      schemaVersion: GROUP_SCHEMA_VERSION,
    },
  };
}

export function validateGroupInvariants(
  content: GroupUnderstandingContent,
  expectedLocalIds: string[]
): { ok: true } | { ok: false; error: GroupFinalizeError } {
  if (content.belongsTogether === "yes" && content.insufficientEvidence) {
    return {
      ok: false,
      error: {
        code: "INCONSISTENT_YES_INSUFFICIENT",
        message: "belongsTogether=yes cannot pair with insufficientEvidence=true",
      },
    };
  }

  const expected = new Set(expectedLocalIds);
  const assessed = new Set(content.memberAssessments.map((m) => m.localId));

  for (const id of assessed) {
    if (!expected.has(id)) {
      return {
        ok: false,
        error: {
          code: "UNKNOWN_MEMBER_ID",
          message: `memberAssessments references unknown localId: ${id}`,
        },
      };
    }
  }

  for (const id of expectedLocalIds) {
    if (!assessed.has(id)) {
      return {
        ok: false,
        error: {
          code: "MISSING_MEMBER_ASSESSMENT",
          message: `memberAssessments missing localId: ${id}`,
        },
      };
    }
  }

  for (const id of content.outlierLocalIds) {
    if (!expected.has(id)) {
      return {
        ok: false,
        error: {
          code: "UNKNOWN_MEMBER_ID",
          message: `outlierLocalIds references unknown localId: ${id}`,
        },
      };
    }
  }

  return { ok: true };
}

function collectBannedText(content: GroupUnderstandingContent): string | null {
  const haystack = [
    content.sharedContextSummary ?? "",
    ...content.supportingEvidence,
    ...content.conflictingEvidence,
    ...content.outerInnerNotes,
    ...content.memberAssessments.flatMap((m) => m.notes),
  ].join("\n");
  const match = haystack.match(COLLECTION_TEXT_BAN);
  return match ? match[0] : null;
}
