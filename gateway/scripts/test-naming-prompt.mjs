/**
 * Deterministic Sprint 8.4 Slice 3 naming-prompt regression tests — NO OpenAI / network.
 * Run: npm run test:naming-prompt
 */
import assert from "node:assert/strict";
import { PROMPT_VERSION } from "../src/config.ts";
import { SYSTEM_PROMPT, buildBatchUserPrompt, buildSingleUserPrompt } from "../src/prompt.ts";

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

check("PROMPT_VERSION is screentidy-org-v3", () => {
  assert.equal(PROMPT_VERSION, "screentidy-org-v3");
});

check("SYSTEM_PROMPT distinguishes TYPE/FACET vs CONTEXT Collection", () => {
  assert.match(SYSTEM_PROMPT, /TYPE \/ FACET vs CONTEXT Collection/i);
  assert.match(SYSTEM_PROMPT, /candidateCollections \/ proposedNewCollection \/ sharedContext/);
});

check("SYSTEM_PROMPT forbids type-as-title / generic category identities", () => {
  assert.match(SYSTEM_PROMPT, /Never invent a Collection from a bare object/i);
  assert.match(SYSTEM_PROMPT, /type\/category labels/i);
  assert.match(SYSTEM_PROMPT, /Travel/);
  assert.match(SYSTEM_PROMPT, /Diagram/);
});

check("SYSTEM_PROMPT requires semantic reuse (same real-world context)", () => {
  assert.match(SYSTEM_PROMPT, /same real-world context/i);
  assert.match(SYSTEM_PROMPT, /overlapping words/i);
  assert.match(SYSTEM_PROMPT, /Same city, airline, merchant, or noun alone is not enough to reuse/i);
});

check("SYSTEM_PROMPT allows abstention / null proposedNewCollection", () => {
  assert.match(SYSTEM_PROMPT, /proposedNewCollection to null/);
  assert.match(SYSTEM_PROMPT, /does not force a title/i);
  assert.match(SYSTEM_PROMPT, /abstain/i);
});

check("SYSTEM_PROMPT forbids over-specific / PII / OCR-dump titles", () => {
  assert.match(SYSTEM_PROMPT, /booking\/confirmation references/i);
  assert.match(SYSTEM_PROMPT, /confirmation codes/i);
  assert.match(SYSTEM_PROMPT, /phone numbers/i);
  assert.match(SYSTEM_PROMPT, /email addresses/i);
  assert.match(SYSTEM_PROMPT, /long verbatim OCR/i);
  assert.match(SYSTEM_PROMPT, /sentence-like/i);
});

check("SYSTEM_PROMPT preserves open vocabulary and forbids taxonomy", () => {
  assert.match(SYSTEM_PROMPT, /Naming vocabulary is open/i);
  assert.match(SYSTEM_PROMPT, /never choose from a fixed list/i);
  assert.match(SYSTEM_PROMPT, /Do not treat any example title/i);
});

check("SYSTEM_PROMPT avoids few-shot canon sticky titles", () => {
  assert.doesNotMatch(SYSTEM_PROMPT, /Japan Trip/);
  assert.doesNotMatch(SYSTEM_PROMPT, /Qatar Airways Booking/);
  assert.doesNotMatch(SYSTEM_PROMPT, /Apartment Setup/);
  assert.doesNotMatch(SYSTEM_PROMPT, /Mom's Birthday Plans/);
});

check("buildBatchUserPrompt includes reuse + abstain + title hygiene cues", () => {
  const text = buildBatchUserPrompt({
    members: [
      {
        localId: "a",
        ocrNormalized: "hotel",
        hasImage: false,
      },
    ],
    eligibleCollections: [{ title: "Existing Context" }],
    allowVisual: false,
  });
  assert.match(text, /same real-world context/i);
  assert.match(text, /word\/city\/merchant\/airline overlap/i);
  assert.match(text, /proposedNewCollection null/i);
  assert.match(text, /booking\/confirmation codes/i);
  assert.match(text, /type\/category label/i);
  assert.match(text, /eligibleCollections:/);
  assert.match(text, /Existing Context/);
});

check("buildSingleUserPrompt still wires eligibleCollections + OCR markers", () => {
  const text = buildSingleUserPrompt({
    ocrNormalized: "boarding pass fragment",
    createdAt: "2026-08-01T00:00:00Z",
    eligibleCollections: [],
    allowVisual: false,
    hasImage: false,
  });
  assert.match(text, /Understand this single screenshot/);
  assert.match(text, /\[OCR_PRESENT\]/);
  assert.match(text, /boarding pass fragment/);
  assert.match(text, /allowVisual=false/);
});

if (process.exitCode) {
  console.error(`\nNaming prompt tests failed (${passed} passed before failure path).`);
} else {
  console.log(`\nAll ${passed} naming-prompt tests passed.`);
}
