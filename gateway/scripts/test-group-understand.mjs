/**
 * Deterministic Sprint 8.3B group-understand Lab tests — NO OpenAI / network.
 * Run: npm run test:group
 */
import assert from "node:assert/strict";
import { GROUP_SCHEMA_VERSION, buildGroupUserPrompt } from "../src/groupPrompt.ts";
import { finalizeGroupUnderstanding } from "../src/groupValidation.ts";
import { GroupUnderstandRequestSchema } from "../src/schemas.ts";

let passed = 0;
function check(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`PASS ${name}`);
  } catch (err) {
    console.error(`FAIL ${name}`);
    console.error(err);
    process.exitCode = 1;
  }
}

const ids = ["flight-1", "email-1", "maps-1"];

check("A valid positive response", () => {
  const raw = {
    belongsTogether: "yes",
    confidence: 0.91,
    sharedContextSummary: "Same trip: flight + hotel email + maps lodging",
    supportingEvidence: ["entity:Etihad", "date:overlap", "descriptor:hotel_details"],
    conflictingEvidence: [],
    memberAssessments: [
      { localId: "flight-1", role: "core", notes: ["itinerary"] },
      { localId: "email-1", role: "core", notes: ["accommodation"] },
      { localId: "maps-1", role: "supporting", notes: ["place"] },
    ],
    outlierLocalIds: [],
    insufficientEvidence: false,
    outerInnerNotes: [],
  };
  const result = finalizeGroupUnderstanding({
    raw,
    expectedLocalIds: ids,
    provider: "openai",
    promptVersion: "screentidy-group-8.3b-v1",
  });
  assert.equal(result.ok, true);
  if (result.ok) {
    assert.equal(result.value.belongsTogether, "yes");
    assert.equal(result.value.schemaVersion, GROUP_SCHEMA_VERSION);
  }
});

check("B valid negative response", () => {
  const raw = {
    belongsTogether: "no",
    confidence: 0.87,
    sharedContextSummary: null,
    supportingEvidence: [],
    conflictingEvidence: ["only_shared_family:travel", "different_cities"],
    memberAssessments: [
      { localId: "a", role: "uncertain", notes: [] },
      { localId: "b", role: "uncertain", notes: [] },
    ],
    outlierLocalIds: [],
    insufficientEvidence: false,
    outerInnerNotes: [],
  };
  const result = finalizeGroupUnderstanding({
    raw,
    expectedLocalIds: ["a", "b"],
    provider: "openai",
    promptVersion: "screentidy-group-8.3b-v1",
  });
  assert.equal(result.ok, true);
  if (result.ok) assert.equal(result.value.belongsTogether, "no");
});

check("C uncertain / insufficient response", () => {
  const raw = {
    belongsTogether: "uncertain",
    confidence: 0.4,
    sharedContextSummary: null,
    supportingEvidence: ["weak_token:city"],
    conflictingEvidence: ["different_purposes"],
    memberAssessments: [
      { localId: "a", role: "uncertain", notes: [] },
      { localId: "b", role: "uncertain", notes: [] },
    ],
    outlierLocalIds: [],
    insufficientEvidence: true,
    outerInnerNotes: [],
  };
  const result = finalizeGroupUnderstanding({
    raw,
    expectedLocalIds: ["a", "b"],
    provider: "openai",
    promptVersion: "screentidy-group-8.3b-v1",
  });
  assert.equal(result.ok, true);
  if (result.ok) {
    assert.equal(result.value.belongsTogether, "uncertain");
    assert.equal(result.value.insufficientEvidence, true);
  }
});

check("D outlier response", () => {
  const raw = {
    belongsTogether: "yes",
    confidence: 0.84,
    sharedContextSummary: "Shopping research; banking shot is unrelated",
    supportingEvidence: ["brand:Beaphar"],
    conflictingEvidence: ["outlier:banking"],
    memberAssessments: [
      { localId: "img", role: "core", notes: [] },
      { localId: "cart", role: "core", notes: [] },
      { localId: "bank", role: "outlier", notes: ["unrelated"] },
    ],
    outlierLocalIds: ["bank"],
    insufficientEvidence: false,
    outerInnerNotes: [],
  };
  const result = finalizeGroupUnderstanding({
    raw,
    expectedLocalIds: ["img", "cart", "bank"],
    provider: "openai",
    promptVersion: "screentidy-group-8.3b-v1",
  });
  assert.equal(result.ok, true);
  if (result.ok) assert.deepEqual(result.value.outlierLocalIds, ["bank"]);
});

check("E strict schema rejection (missing belongsTogether)", () => {
  const result = finalizeGroupUnderstanding({
    raw: { confidence: 0.5, memberAssessments: [], outlierLocalIds: [], insufficientEvidence: true, outerInnerNotes: [], supportingEvidence: [], conflictingEvidence: [], sharedContextSummary: null },
    expectedLocalIds: ["a", "b"],
    provider: "openai",
    promptVersion: "screentidy-group-8.3b-v1",
  });
  assert.equal(result.ok, false);
  if (!result.ok) assert.equal(result.error.code, "MODEL_OUTPUT_INVALID");
});

check("F forbidden Collection-related output", () => {
  const result = finalizeGroupUnderstanding({
    raw: {
      belongsTogether: "yes",
      confidence: 0.9,
      sharedContextSummary: "x",
      supportingEvidence: [],
      conflictingEvidence: [],
      memberAssessments: [
        { localId: "a", role: "core", notes: [] },
        { localId: "b", role: "core", notes: [] },
      ],
      outlierLocalIds: [],
      insufficientEvidence: false,
      outerInnerNotes: [],
      proposedNewCollection: { title: "Japan Trip", emoji: "✈️", confidence: 0.9 },
    },
    expectedLocalIds: ["a", "b"],
    provider: "openai",
    promptVersion: "screentidy-group-8.3b-v1",
  });
  assert.equal(result.ok, false);
  if (!result.ok) assert.equal(result.error.code, "FORBIDDEN_COLLECTION_FIELDS");
});

check("G group >8 rejected by request schema", () => {
  const members = Array.from({ length: 9 }, (_, i) => ({ localId: `m${i}` }));
  const parsed = GroupUnderstandRequestSchema.safeParse({
    correlationId: "c1",
    schemaVersion: GROUP_SCHEMA_VERSION,
    members,
  });
  assert.equal(parsed.success, false);
});

check("H malformed / duplicate member IDs rejected", () => {
  const dup = GroupUnderstandRequestSchema.safeParse({
    correlationId: "c1",
    members: [
      { localId: "a", ocrText: "x" },
      { localId: "a", ocrText: "y" },
    ],
  });
  assert.equal(dup.success, false);

  const imageLeak = GroupUnderstandRequestSchema.safeParse({
    correlationId: "c1",
    members: [
      { localId: "a", imageBase64: "AAAA" },
      { localId: "b" },
    ],
  });
  assert.equal(imageLeak.success, false);

  const emptyId = GroupUnderstandRequestSchema.safeParse({
    correlationId: "c1",
    members: [{ localId: "" }, { localId: "b" }],
  });
  assert.equal(emptyId.success, false);
});

check("I outer/inner evidence without forcing positive merge", () => {
  const raw = {
    belongsTogether: "uncertain",
    confidence: 0.44,
    sharedContextSummary: null,
    supportingEvidence: ["descriptor:gameplay_overlap"],
    conflictingEvidence: [
      "outer_container:youtube_video_player",
      "inner_subject:mobile_legends",
      "native_game_screenshot",
    ],
    memberAssessments: [
      { localId: "yt", role: "uncertain", notes: ["outer_inner_ambiguous"] },
      { localId: "game", role: "uncertain", notes: ["native_gameplay"] },
    ],
    outlierLocalIds: [],
    insufficientEvidence: true,
    outerInnerNotes: [
      "Semantic gameplay overlap alone does not prove the same real-world context",
    ],
  };
  const result = finalizeGroupUnderstanding({
    raw,
    expectedLocalIds: ["yt", "game"],
    provider: "openai",
    promptVersion: "screentidy-group-8.3b-v1",
  });
  assert.equal(result.ok, true);
  if (result.ok) {
    assert.equal(result.value.belongsTogether, "uncertain");
    assert.ok(result.value.outerInnerNotes.length > 0);
  }
});

check("yes + insufficientEvidence rejected", () => {
  const result = finalizeGroupUnderstanding({
    raw: {
      belongsTogether: "yes",
      confidence: 0.9,
      sharedContextSummary: "forced",
      supportingEvidence: [],
      conflictingEvidence: [],
      memberAssessments: [
        { localId: "a", role: "core", notes: [] },
        { localId: "b", role: "core", notes: [] },
      ],
      outlierLocalIds: [],
      insufficientEvidence: true,
      outerInnerNotes: [],
    },
    expectedLocalIds: ["a", "b"],
    provider: "openai",
    promptVersion: "screentidy-group-8.3b-v1",
  });
  assert.equal(result.ok, false);
  if (!result.ok) assert.equal(result.error.code, "INCONSISTENT_YES_INSUFFICIENT");
});

check("user prompt is evidence-only (no image flag)", () => {
  const text = buildGroupUserPrompt({
    members: [
      { localId: "a", ocrText: "hello", platform: "gmail" },
      { localId: "b", openDescriptors: ["hotel_details"] },
    ],
  });
  assert.match(text, /imagesAttached=false/);
  assert.match(text, /evidenceOnly=true/);
  assert.match(text, /precisionFirst=true/);
  assert.doesNotMatch(text, /imageBase64/);
});

check("collection title text leakage rejected", () => {
  const result = finalizeGroupUnderstanding({
    raw: {
      belongsTogether: "no",
      confidence: 0.5,
      sharedContextSummary: "please create collection called Travel",
      supportingEvidence: [],
      conflictingEvidence: [],
      memberAssessments: [
        { localId: "a", role: "uncertain", notes: [] },
        { localId: "b", role: "uncertain", notes: [] },
      ],
      outlierLocalIds: [],
      insufficientEvidence: false,
      outerInnerNotes: [],
    },
    expectedLocalIds: ["a", "b"],
    provider: "openai",
    promptVersion: "screentidy-group-8.3b-v1",
  });
  assert.equal(result.ok, false);
  if (!result.ok) assert.equal(result.error.code, "FORBIDDEN_COLLECTION_FIELDS");
});

if (process.exitCode) {
  console.error(`\nGroup understand tests FAILED (${passed} passed before failure)`);
} else {
  console.log(`\nAll group understand tests passed (${passed})`);
}
